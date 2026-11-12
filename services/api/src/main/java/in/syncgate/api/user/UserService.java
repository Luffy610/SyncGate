package in.syncgate.api.user;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import in.syncgate.api.domain.Role;
import in.syncgate.api.domain.Wire;
import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Admin users and PINs (ADR-0004). PINs and the recovery code are stored only
 * as Argon2id hashes. Wrong attempts are counted in the database, so the
 * lockout survives restarts and cannot be dodged by switching connections.
 */
@Service
public class UserService {

    public record AppUser(UUID id, String name, Role role) {}

    /** Outcome of a PIN check; the controller turns it into an HTTP answer. */
    public sealed interface PinResult {
        record Ok(AppUser user) implements PinResult {}

        record Wrong(int attemptsLeft, Duration lockedFor) implements PinResult {}

        record Locked(Duration remaining) implements PinResult {}
    }

    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final int FREE_ATTEMPTS = 5;
    private static final Duration MAX_LOCKOUT = Duration.ofMinutes(15);

    private final JdbcClient jdbc;
    private final PasswordEncoder encoder;
    private final AppClock clock;
    private final AuditService audit;
    private final SecureRandom random = new SecureRandom();
    private final String dummyHash;
    private volatile boolean ownerExists;

    public UserService(JdbcClient jdbc, PasswordEncoder encoder, AppClock clock, AuditService audit) {
        this.jdbc = jdbc;
        this.encoder = encoder;
        this.clock = clock;
        this.audit = audit;
        this.dummyHash = encoder.encode("000000");
    }

    /** Once true it stays true, so the hot path costs nothing after setup. */
    public boolean ownerExists() {
        if (ownerExists) {
            return true;
        }
        boolean exists = jdbc.sql("SELECT COUNT(*) FROM users WHERE role = 'owner'").query(Integer.class).single() > 0;
        ownerExists = exists;
        return exists;
    }

    /** Creates the owner plus empty admin and gate-operator accounts. */
    @Transactional
    public String createOwner(String pin) {
        if (ownerExists()) {
            throw ApiException.conflict("SETUP_DONE", "This device is already set up");
        }
        String recovery = newRecoveryCode();
        Instant now = clock.now();
        try {
            insertUser("Owner", Role.OWNER, encoder.encode(pin), encoder.encode(normalise(recovery)), now);
            insertUser("Admin", Role.ADMIN, null, null, now);
            insertUser("Gate operator", Role.GATE_OPERATOR, null, null, now);
        } catch (DuplicateKeyException e) {
            throw ApiException.conflict("SETUP_DONE", "This device is already set up");
        }
        ownerExists = true;
        audit.record("Owner", "owner.created", null);
        return recovery;
    }

    public AppUser ownerUser() {
        return findByRole(Role.OWNER);
    }

    @Transactional
    public PinResult verifyPin(Role role, String pin) {
        if (!role.isUser()) {
            throw ApiException.invalid("Unknown role");
        }
        var row = jdbc.sql("SELECT id, name, pin_hash, failed_attempts, locked_until FROM users "
                        + "WHERE role = :r AND active = TRUE FOR UPDATE")
                .param("r", Wire.of(role))
                .query((rs, i) -> new Object[] {Db.uuid(rs, "id"), rs.getString("name"), rs.getString("pin_hash"),
                    rs.getInt("failed_attempts"), Db.instant(rs, "locked_until")})
                .optional();
        if (row.isEmpty() || row.get()[2] == null) {
            encoder.matches(pin, dummyHash); // keep timing the same for unknown accounts
            return new PinResult.Wrong(0, null);
        }
        Object[] r = row.get();
        UUID id = (UUID) r[0];
        Instant now = clock.now();
        Instant lockedUntil = (Instant) r[4];
        if (lockedUntil != null && lockedUntil.isAfter(now)) {
            return new PinResult.Locked(Duration.between(now, lockedUntil));
        }
        if (encoder.matches(pin, (String) r[2])) {
            jdbc.sql("UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = :id")
                    .param("id", id).update();
            return new PinResult.Ok(new AppUser(id, (String) r[1], role));
        }
        return recordFailure(id, (Integer) r[3] + 1, now, role);
    }

    /** Owner PIN reset with the recovery code shown once at setup. */
    @Transactional
    public PinResult resetOwnerPin(String recoveryCode, String newPin) {
        var row = jdbc.sql("SELECT id, recovery_hash, failed_attempts, locked_until FROM users "
                        + "WHERE role = 'owner' FOR UPDATE")
                .query((rs, i) -> new Object[] {Db.uuid(rs, "id"), rs.getString("recovery_hash"),
                    rs.getInt("failed_attempts"), Db.instant(rs, "locked_until")})
                .optional();
        if (row.isEmpty()) {
            encoder.matches(recoveryCode, dummyHash);
            return new PinResult.Wrong(0, null);
        }
        Object[] r = row.get();
        UUID id = (UUID) r[0];
        Instant now = clock.now();
        Instant lockedUntil = (Instant) r[3];
        if (lockedUntil != null && lockedUntil.isAfter(now)) {
            return new PinResult.Locked(Duration.between(now, lockedUntil));
        }
        if (r[1] != null && encoder.matches(normalise(recoveryCode), (String) r[1])) {
            jdbc.sql("UPDATE users SET pin_hash = :p, failed_attempts = 0, locked_until = NULL WHERE id = :id")
                    .param("p", encoder.encode(newPin)).param("id", id).update();
            audit.record("Owner", "owner.pin_reset", "recovery code");
            return new PinResult.Ok(new AppUser(id, "Owner", Role.OWNER));
        }
        return recordFailure(id, (Integer) r[2] + 1, now, Role.OWNER);
    }

    public List<AppUser> users() {
        return jdbc.sql("SELECT id, name, role FROM users WHERE active = TRUE ORDER BY created_at, name")
                .query((rs, i) -> new AppUser(Db.uuid(rs, "id"), rs.getString("name"),
                        Wire.parse(Role.class, rs.getString("role"))))
                .list();
    }

    @Transactional
    public void setPin(UUID userId, String pin, String actor) {
        int changed = jdbc.sql("UPDATE users SET pin_hash = :p, failed_attempts = 0, locked_until = NULL "
                        + "WHERE id = :id AND active = TRUE")
                .param("p", encoder.encode(pin)).param("id", userId).update();
        if (changed == 0) {
            throw ApiException.notFound("User");
        }
        audit.record(actor, "user.pin_changed", userId.toString());
    }

    private PinResult recordFailure(UUID id, int failures, Instant now, Role role) {
        Duration lock = lockoutAfter(failures);
        Instant until = lock.isZero() ? null : now.plus(lock);
        jdbc.sql("UPDATE users SET failed_attempts = :f, locked_until = :u WHERE id = :id")
                .param("f", failures).param("u", Db.ts(until)).param("id", id).update();
        if (!lock.isZero() && failures == FREE_ATTEMPTS) {
            audit.record(Wire.of(role), "auth.locked_out", "after " + failures + " wrong attempts");
        }
        return new PinResult.Wrong(Math.max(0, FREE_ATTEMPTS - failures), lock.isZero() ? null : lock);
    }

    /** Mirrors {@code PinPolicy.lockoutAfter} in the Flutter sg_domain package. */
    public static Duration lockoutAfter(int failures) {
        if (failures < FREE_ATTEMPTS) {
            return Duration.ZERO;
        }
        int steps = Math.min(failures - FREE_ATTEMPTS, 10);
        Duration lock = Duration.ofSeconds(30L * (1L << steps));
        return lock.compareTo(MAX_LOCKOUT) > 0 ? MAX_LOCKOUT : lock;
    }

    private AppUser findByRole(Role role) {
        return jdbc.sql("SELECT id, name FROM users WHERE role = :r")
                .param("r", Wire.of(role))
                .query((rs, i) -> new AppUser(Db.uuid(rs, "id"), rs.getString("name"), role))
                .optional()
                .orElseThrow(() -> ApiException.notFound("User"));
    }

    private void insertUser(String name, Role role, String pinHash, String recoveryHash, Instant now) {
        jdbc.sql("INSERT INTO users (id, name, role, pin_hash, recovery_hash, created_at) "
                        + "VALUES (:id, :name, :role, :pin, :rec, :at)")
                .param("id", Uuid7.next())
                .param("name", name)
                .param("role", Wire.of(role))
                .param("pin", pinHash)
                .param("rec", recoveryHash)
                .param("at", Db.ts(now))
                .update();
    }

    private String newRecoveryCode() {
        StringBuilder code = new StringBuilder();
        for (int i = 0; i < 12; i++) {
            if (i > 0 && i % 4 == 0) {
                code.append('-');
            }
            code.append(ALPHABET.charAt(random.nextInt(ALPHABET.length())));
        }
        return code.toString();
    }

    static String normalise(String recoveryCode) {
        return recoveryCode.replace("-", "").replace(" ", "").toUpperCase();
    }
}
