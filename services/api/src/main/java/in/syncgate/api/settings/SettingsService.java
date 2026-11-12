package in.syncgate.api.settings;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import in.syncgate.api.domain.Enums.AppMode;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.user.UserService;
import java.util.Set;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Single-row settings store. */
@Service
public class SettingsService {

    private static final Set<String> LANGUAGES = Set.of("en", "hi", "gu", "ta", "pa", "mr");

    private final JdbcClient jdbc;
    private final AppClock clock;
    private final AuditService audit;
    private final UserService users;

    public SettingsService(JdbcClient jdbc, AppClock clock, AuditService audit, UserService users) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.audit = audit;
        this.users = users;
    }

    @Transactional
    public SettingsController.SettingsDto load() {
        jdbc.sql("""
                INSERT INTO app_settings (id, updated_at)
                SELECT 1, :now WHERE NOT EXISTS (SELECT 1 FROM app_settings WHERE id = 1)""")
                .param("now", Db.ts(clock.now()))
                .update();
        return jdbc.sql("""
                SELECT mode, setup_step, language, idle_minutes, cooldown_seconds, voice_volume,
                       screen_fill_light, use_24_hour_clock, remind_backup_days, auto_backup,
                       gate_operator_id, biometric_enabled, backup_passphrase_set
                FROM app_settings WHERE id = 1""")
                .query((rs, i) -> new SettingsController.SettingsDto(rs.getString(1), rs.getInt(2), rs.getString(3),
                        rs.getInt(4), rs.getInt(5), rs.getDouble(6), rs.getBoolean(7), rs.getBoolean(8),
                        rs.getInt(9), rs.getBoolean(10), rs.getString(11), rs.getBoolean(12), rs.getBoolean(13)))
                .single();
    }

    @Transactional
    public void save(SettingsController.SettingsDto in, boolean full, String actor) {
        AppMode mode = Wire.parse(AppMode.class, in.mode());
        SettingsController.SettingsDto current = load();
        if (mode == AppMode.SETUP && users.ownerExists()) {
            throw ApiException.conflict("SETUP_DONE", "Setup is already finished");
        }
        if (full) {
            if (!LANGUAGES.contains(in.language())) {
                throw ApiException.invalid("Unknown language");
            }
            jdbc.sql("""
                    UPDATE app_settings SET mode = :mode, setup_step = :step, language = :lang,
                        idle_minutes = :idle, cooldown_seconds = :cool, voice_volume = :vol,
                        screen_fill_light = :fill, use_24_hour_clock = :h24, remind_backup_days = :remind,
                        auto_backup = :auto, gate_operator_id = :op, biometric_enabled = :bio,
                        updated_at = :now WHERE id = 1""")
                    .param("mode", Wire.of(mode))
                    .param("step", in.setupStep())
                    .param("lang", in.language())
                    .param("idle", in.idleMinutes())
                    .param("cool", in.cooldownSeconds())
                    .param("vol", in.voiceVolume())
                    .param("fill", in.screenFillLight())
                    .param("h24", in.use24HourClock())
                    .param("remind", in.remindBackupDays())
                    .param("auto", in.autoBackup())
                    .param("op", in.gateOperatorId().strip())
                    .param("bio", in.biometricEnabled())
                    .param("now", Db.ts(clock.now()))
                    .update();
            if (!current.language().equals(in.language()) || current.cooldownSeconds() != in.cooldownSeconds()
                    || current.idleMinutes() != in.idleMinutes() || current.autoBackup() != in.autoBackup()) {
                audit.record(actor, "settings.changed", "language/cooldown/idle/backup");
            }
        } else {
            jdbc.sql("UPDATE app_settings SET mode = :mode, setup_step = :step, updated_at = :now WHERE id = 1")
                    .param("mode", Wire.of(mode))
                    .param("step", in.setupStep())
                    .param("now", Db.ts(clock.now()))
                    .update();
        }
    }

    /** Called by the backup service once a passphrase has been stored. */
    @Transactional
    public void markPassphraseSet() {
        load();
        jdbc.sql("UPDATE app_settings SET backup_passphrase_set = TRUE WHERE id = 1").update();
    }

    public int cooldownSeconds() {
        return load().cooldownSeconds();
    }
}
