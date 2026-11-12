package in.syncgate.api.backup;

import in.syncgate.api.attendance.AttendanceService;
import in.syncgate.api.audit.AuditService;
import in.syncgate.api.backup.BackupCodec.BackupException;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.ChainService;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import in.syncgate.api.config.SyncgateProperties;
import in.syncgate.api.settings.SettingsService;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.sql.ResultSetMetaData;
import java.sql.SQLException;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import tools.jackson.databind.json.JsonMapper;

/**
 * Encrypted backup and restore (ADR-0013, FR-OFF-02..05).
 *
 * <p>A backup is every business table (never face templates; those do not
 * exist server-side) serialised to JSON and sealed by {@link BackupCodec}
 * with a key derived from the owner's passphrase. The passphrase itself is
 * never stored; a key derived from it is kept wrapped under the server master
 * key so the nightly job can run unattended.
 *
 * <p>Restore is only allowed into a pristine database, loads inside one
 * transaction, then re-verifies both hash chains and the manifest counts; any
 * mismatch rolls the whole restore back.
 */
@Service
public class BackupService {

    private static final Logger log = LoggerFactory.getLogger(BackupService.class);

    /** Insert order respects foreign keys. Backups and keys are deliberately not included. */
    static final List<String> TABLES = List.of("app_settings", "users", "departments", "shifts", "workers", "consents",
            "attendance_events", "exceptions", "audit_log", "licence", "exports", "chain_heads");

    public record BackupInfo(Instant lastBackupAt, String destination) {}

    public record BackupRecord(UUID id, Instant createdAt, String destination, String fileName, String sha256,
            long sizeBytes) {}

    private final JdbcClient jdbc;
    private final AppClock clock;
    private final SyncgateProperties props;
    private final BackupStore store;
    private final AuditService audit;
    private final AttendanceService attendance;
    private final ChainService chain;
    private final SettingsService settings;
    private final JsonMapper json = JsonMapper.builder().build();
    private final SecureRandom random = new SecureRandom();

    public BackupService(JdbcClient jdbc, AppClock clock, SyncgateProperties props, BackupStore store,
            AuditService audit, AttendanceService attendance, ChainService chain, SettingsService settings) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.props = props;
        this.store = store;
        this.audit = audit;
        this.attendance = attendance;
        this.chain = chain;
        this.settings = settings;
    }

    // ---- passphrase --------------------------------------------------------

    @Transactional
    public void setPassphrase(String passphrase, String actor) {
        if (passphrase == null || passphrase.length() < 8 || passphrase.length() > 128) {
            throw ApiException.invalid("The passphrase must be 8 to 128 characters");
        }
        byte[] salt = BackupCodec.newSalt();
        byte[] key = BackupCodec.deriveKey(passphrase, salt, props.backup().argon2MemoryKib(),
                props.backup().argon2Iterations());
        jdbc.sql("DELETE FROM backup_key").update();
        jdbc.sql("INSERT INTO backup_key (id, salt, wrapped, verifier) VALUES (1, :s, :w, :v)")
                .param("s", HexFormat.of().formatHex(salt)).param("w", wrap(key)).param("v", verifier(key)).update();
        settings.markPassphraseSet();
        audit.record(actor, "backup.passphrase_set", null);
    }

    public boolean passphraseSet() {
        return jdbc.sql("SELECT COUNT(*) FROM backup_key").query(Integer.class).single() > 0;
    }

    // ---- create ------------------------------------------------------------

    @Transactional
    public BackupRecord backupNow(String actor) {
        var keyRow = jdbc.sql("SELECT salt, wrapped FROM backup_key WHERE id = 1")
                .query((rs, i) -> new String[] {rs.getString(1), rs.getString(2)}).optional()
                .orElseThrow(() -> ApiException.conflict("PASSPHRASE_NOT_SET", "Set a backup passphrase first"));
        byte[] salt = HexFormat.of().parseHex(keyRow[0]);
        byte[] key = unwrap(keyRow[1]);

        byte[] dump = json.writeValueAsBytes(dump());
        byte[] file = BackupCodec.encrypt(dump, key, new BackupCodec.Kdf(props.backup().argon2MemoryKib(),
                props.backup().argon2Iterations(), salt));

        Instant now = clock.now();
        UUID id = Uuid7.next();
        String name = "syncgate-" + now.atZone(clock.zone()).toLocalDate() + "-"
                + id.toString().substring(0, 8) + ".sgbackup";
        store.put(name, file);
        BackupRecord record = new BackupRecord(id, now, store.destinationName(), name, sha256(file), file.length);
        jdbc.sql("""
                INSERT INTO backups (id, created_at, destination, file_name, sha256, size_bytes, created_by)
                VALUES (:id, :at, :d, :n, :s, :z, :by)""")
                .param("id", id).param("at", Db.ts(now)).param("d", record.destination()).param("n", name)
                .param("s", record.sha256()).param("z", record.sizeBytes()).param("by", actor).update();
        audit.record(actor, "backup.created", name);
        prune();
        return record;
    }

    /** Nightly automatic backup (default 22:30). Skipped when switched off or unconfigured. */
    @Scheduled(cron = "${syncgate.backup.cron}", zone = "${syncgate.zone}")
    public void scheduled() {
        try {
            if (settings.load().autoBackup() && passphraseSet()) {
                backupNow("System");
            }
        } catch (RuntimeException e) {
            log.warn("Scheduled backup failed: {}", e.toString());
        }
    }

    public List<BackupRecord> list() {
        return jdbc.sql("SELECT id, created_at, destination, file_name, sha256, size_bytes FROM backups "
                        + "ORDER BY created_at DESC")
                .query((rs, i) -> new BackupRecord(Db.uuid(rs, "id"), Db.instant(rs, "created_at"),
                        rs.getString("destination"), rs.getString("file_name"), rs.getString("sha256"),
                        rs.getLong("size_bytes")))
                .list();
    }

    public BackupInfo info() {
        var latest = list().stream().findFirst();
        return new BackupInfo(latest.map(BackupRecord::createdAt).orElse(null),
                latest.map(BackupRecord::destination).orElse(null));
    }

    public byte[] download(UUID id) {
        BackupRecord record = list().stream().filter(b -> b.id().equals(id)).findFirst()
                .orElseThrow(() -> ApiException.notFound("Backup"));
        return store.get(record.fileName());
    }

    private void prune() {
        List<BackupRecord> all = list();
        for (int i = props.backup().retention(); i < all.size(); i++) {
            store.delete(all.get(i).fileName());
            jdbc.sql("DELETE FROM backups WHERE id = :id").param("id", all.get(i).id()).update();
        }
    }

    // ---- restore -----------------------------------------------------------

    /** Loads a backup into a pristine database. All or nothing. */
    @Transactional
    @SuppressWarnings("unchecked")
    public int restore(byte[] file, String passphrase, String actor) {
        if (passphrase == null || passphrase.isEmpty()) {
            throw ApiException.invalid("Enter the backup passphrase");
        }
        requirePristine();
        Map<String, Object> dump;
        try {
            BackupCodec.Kdf kdf = BackupCodec.readKdf(file);
            byte[] key = BackupCodec.deriveKey(passphrase, kdf.salt(), kdf.memoryKib(), kdf.iterations());
            dump = json.readValue(BackupCodec.decrypt(file, key), Map.class);
        } catch (BackupException e) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY,
                    e.wrongPassphrase() ? "BAD_PASSPHRASE" : "BACKUP_CORRUPT", e.getMessage());
        } catch (RuntimeException e) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "BACKUP_CORRUPT", "The backup file is damaged");
        }

        Map<String, Object> tables = (Map<String, Object>) dump.get("tables");
        Map<String, Object> manifest = (Map<String, Object>) dump.get("manifest");
        if (tables == null || manifest == null || !Integer.valueOf(1).equals(dump.get("format"))) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "BACKUP_CORRUPT", "The backup file is damaged");
        }

        for (String table : List.of("chain_heads", "exports", "licence", "departments", "app_settings")) {
            jdbc.sql("DELETE FROM " + table).update();
        }
        int total = 0;
        Map<String, Object> counts = (Map<String, Object>) manifest.get("counts");
        for (String table : TABLES) {
            List<Map<String, Object>> rows = (List<Map<String, Object>>) tables.getOrDefault(table, List.of());
            if (counts == null || !Integer.valueOf(rows.size()).equals(counts.get(table))) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "BACKUP_CORRUPT", "The backup is incomplete");
            }
            insertRows(table, rows);
            total += rows.size();
        }

        // Tamper checks: both chains must verify and end at the recorded heads.
        var attendanceCheck = attendance.verify();
        var auditCheck = audit.verify();
        if (!attendanceCheck.ok() || !auditCheck.ok()
                || !String.valueOf(chain.head(AttendanceService.CHAIN)).equals(String.valueOf(manifest.get("attendanceHead")))
                || !String.valueOf(chain.head(AuditService.CHAIN)).equals(String.valueOf(manifest.get("auditHead")))) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "BACKUP_TAMPERED",
                    "The records in this backup do not add up and cannot be restored");
        }

        // Face codes never travel with a backup: everyone must enrol again on this device.
        jdbc.sql("UPDATE workers SET face_status = 'needsFace'").update();
        audit.record(actor, "backup.restored", total + " records");
        return total;
    }

    private void requirePristine() {
        for (String table : List.of("users", "workers", "shifts", "attendance_events", "audit_log")) {
            if (jdbc.sql("SELECT COUNT(*) FROM " + table).query(Integer.class).single() > 0) {
                throw ApiException.conflict("NOT_EMPTY",
                        "Restore is only possible on a fresh install, before setup");
            }
        }
    }

    // ---- dump / load helpers ----------------------------------------------

    private Map<String, Object> dump() {
        Map<String, Object> tables = new LinkedHashMap<>();
        Map<String, Object> counts = new LinkedHashMap<>();
        for (String table : TABLES) {
            List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM " + table + orderBy(table))
                    .query((rs, i) -> readRow(rs)).list();
            tables.put(table, rows);
            counts.put(table, rows.size());
        }
        Map<String, Object> manifest = new LinkedHashMap<>();
        manifest.put("counts", counts);
        manifest.put("auditHead", chain.head(AuditService.CHAIN));
        manifest.put("attendanceHead", chain.head(AttendanceService.CHAIN));
        manifest.put("createdAt", clock.now().toString());
        Map<String, Object> dump = new LinkedHashMap<>();
        dump.put("format", 1);
        dump.put("tables", tables);
        dump.put("manifest", manifest);
        return dump;
    }

    private static String orderBy(String table) {
        return switch (table) {
            case "attendance_events", "audit_log" -> " ORDER BY seq";
            default -> "";
        };
    }

    private Map<String, Object> readRow(java.sql.ResultSet rs) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        Map<String, Object> row = new LinkedHashMap<>();
        for (int c = 1; c <= meta.getColumnCount(); c++) {
            // Ask the driver for java.time types explicitly: PostgreSQL and H2 return
            // different legacy classes from plain getObject, and time zones must not leak in.
            String type = meta.getColumnTypeName(c).toUpperCase();
            Object value;
            if (type.contains("TIMESTAMP")) {
                OffsetDateTime time = rs.getObject(c, OffsetDateTime.class);
                value = time == null ? null : time.withOffsetSameInstant(ZoneOffset.UTC).toInstant().toString();
            } else if (type.equals("DATE")) {
                LocalDate date = rs.getObject(c, LocalDate.class);
                value = date == null ? null : date.toString();
            } else {
                value = rs.getObject(c);
                if (value instanceof UUID) {
                    value = value.toString();
                }
            }
            row.put(meta.getColumnLabel(c).toLowerCase(), value);
        }
        return row;
    }

    /**
     * Column names come from the backup file, which is untrusted. They are
     * only used after being matched against the live table's own columns, and
     * values are always bound as parameters.
     */
    private void insertRows(String table, List<Map<String, Object>> rows) {
        if (rows.isEmpty()) {
            return;
        }
        Map<String, String> types = columnTypes(table);
        for (Map<String, Object> row : rows) {
            if (!types.keySet().containsAll(row.keySet())) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "BACKUP_CORRUPT",
                        "The backup does not match this version of SyncGate");
            }
            List<String> columns = new ArrayList<>(row.keySet());
            String sql = "INSERT INTO " + table + " (" + String.join(", ", columns) + ") VALUES ("
                    + String.join(", ", columns.stream().map(c -> ":" + c).toList()) + ")";
            var statement = jdbc.sql(sql);
            for (String column : columns) {
                statement = statement.param(column, convert(types.get(column), row.get(column)));
            }
            statement.update();
        }
    }

    private Map<String, String> columnTypes(String table) {
        return jdbc.sql("SELECT * FROM " + table + " WHERE 1 = 0").query(rs -> {
            Map<String, String> types = new LinkedHashMap<>();
            ResultSetMetaData meta = rs.getMetaData();
            for (int c = 1; c <= meta.getColumnCount(); c++) {
                types.put(meta.getColumnLabel(c).toLowerCase(), meta.getColumnTypeName(c).toUpperCase());
            }
            return types;
        });
    }

    static Object convert(String type, Object value) {
        if (value == null) {
            return null;
        }
        String text = value.toString();
        if (type.contains("UUID")) {
            return UUID.fromString(text);
        }
        if (type.contains("TIMESTAMP")) {
            return OffsetDateTime.parse(text).withOffsetSameInstant(ZoneOffset.UTC);
        }
        if (type.equals("DATE")) {
            return LocalDate.parse(text);
        }
        if (type.contains("BOOL")) {
            return Boolean.valueOf(text);
        }
        if (type.equals("BIGINT") || type.equals("INT8")) {
            return Long.valueOf(text);
        }
        if (type.contains("INT")) {
            return Integer.valueOf(text);
        }
        if (type.contains("DOUBLE") || type.contains("FLOAT") || type.contains("NUMERIC")) {
            return Double.valueOf(text);
        }
        return text;
    }

    // ---- key wrapping ------------------------------------------------------

    private byte[] masterKey() {
        return Base64.getDecoder().decode(props.security().masterKey());
    }

    private String wrap(byte[] key) {
        try {
            byte[] nonce = new byte[12];
            random.nextBytes(nonce);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(masterKey(), "AES"), new GCMParameterSpec(128, nonce));
            byte[] sealed = cipher.doFinal(key);
            byte[] all = new byte[nonce.length + sealed.length];
            System.arraycopy(nonce, 0, all, 0, nonce.length);
            System.arraycopy(sealed, 0, all, nonce.length, sealed.length);
            return Base64.getEncoder().encodeToString(all);
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private byte[] unwrap(String wrapped) {
        try {
            byte[] all = Base64.getDecoder().decode(wrapped);
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, new SecretKeySpec(masterKey(), "AES"),
                    new GCMParameterSpec(128, all, 0, 12));
            return cipher.doFinal(all, 12, all.length - 12);
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException("backup key cannot be unwrapped (wrong master key?)", e);
        }
    }

    private static String verifier(byte[] key) {
        return sha256(("verify:" + HexFormat.of().formatHex(key)).getBytes(StandardCharsets.UTF_8));
    }

    static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
