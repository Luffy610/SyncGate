package in.syncgate.api.config;

import java.time.Duration;
import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

/** Typed view of the {@code syncgate.*} settings in application*.yml. */
@ConfigurationProperties("syncgate")
public record SyncgateProperties(
        @DefaultValue("Asia/Kolkata") String zone,
        @DefaultValue Clock clock,
        @DefaultValue Security security,
        @DefaultValue Backup backup,
        @DefaultValue Licence licence) {

    /** Optional demo start time; the clock then runs in real time from it. */
    public record Clock(String start) {}

    public record Security(
            String jwtSecret,
            String masterKey,
            @DefaultValue List<String> deviceKeys,
            @DefaultValue("30m") Duration adminTokenTtl,
            @DefaultValue("30d") Duration deviceTokenTtl,
            @DefaultValue("16384") int argon2MemoryKib,
            @DefaultValue("3") int argon2Iterations,
            @DefaultValue List<String> allowedOrigins) {}

    public record Backup(
            @DefaultValue("./data/backups") String dir,
            @DefaultValue("10") int retention,
            @DefaultValue("0 30 22 * * *") String cron,
            @DefaultValue("65536") int argon2MemoryKib,
            @DefaultValue("3") int argon2Iterations) {}

    public record Licence(
            @DefaultValue("false") boolean mock,
            @DefaultValue("30") int trialDays,
            @DefaultValue("365") int validityDays,
            @DefaultValue("14") int checkinDays,
            @DefaultValue("30") int graceDays) {}
}
