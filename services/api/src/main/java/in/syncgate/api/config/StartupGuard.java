package in.syncgate.api.config;

import java.util.Base64;
import org.springframework.beans.factory.InitializingBean;
import org.springframework.core.env.Environment;
import org.springframework.core.env.Profiles;
import org.springframework.stereotype.Component;

/**
 * Fails fast on weak or missing secrets. Production must never run on a
 * development secret, so every check is stricter when the {@code prod}
 * profile is active.
 */
@Component
public class StartupGuard implements InitializingBean {

    private final SyncgateProperties props;
    private final Environment env;

    public StartupGuard(SyncgateProperties props, Environment env) {
        this.props = props;
        this.env = env;
    }

    @Override
    public void afterPropertiesSet() {
        var sec = props.security();
        require(sec.jwtSecret() != null && sec.jwtSecret().getBytes().length >= 32,
                "syncgate.security.jwt-secret must be at least 32 bytes");
        byte[] master;
        try {
            master = Base64.getDecoder().decode(sec.masterKey() == null ? "" : sec.masterKey());
        } catch (IllegalArgumentException e) {
            throw new IllegalStateException("syncgate.security.master-key must be base64");
        }
        require(master.length == 32, "syncgate.security.master-key must decode to 32 bytes");
        require(!sec.deviceKeys().isEmpty(), "syncgate.security.device-keys must not be empty");
        for (String key : sec.deviceKeys()) {
            require(key != null && key.length() >= 16, "each device key must be at least 16 characters");
        }
        if (env.acceptsProfiles(Profiles.of("prod"))) {
            require(!sec.jwtSecret().contains("dev-only") && !sec.jwtSecret().contains("test-"),
                    "a development JWT secret is not allowed in prod");
            require(sec.deviceKeys().stream().noneMatch(k -> k.contains("dev-device") || k.contains("test-")),
                    "a development device key is not allowed in prod");
            require(sec.argon2MemoryKib() >= 16384, "argon2 memory must be at least 16 MiB in prod");
            require(!props.licence().mock(), "licence.mock must be off in prod");
            require(props.clock().start() == null, "syncgate.clock.start (demo clock) must be unset in prod");
        }
    }

    private static void require(boolean ok, String message) {
        if (!ok) {
            throw new IllegalStateException("Unsafe configuration: " + message);
        }
    }
}
