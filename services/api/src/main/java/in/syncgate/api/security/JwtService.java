package in.syncgate.api.security;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import in.syncgate.api.config.SyncgateProperties;
import in.syncgate.api.domain.Role;
import in.syncgate.api.domain.Wire;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwsHeader;
import org.springframework.security.oauth2.jwt.JwtClaimsSet;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.JwtEncoderParameters;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.stereotype.Component;

/**
 * Issues and verifies short-lived HS256 access tokens with Spring Security's
 * Nimbus support (no hand-rolled crypto). Admin tokens live 30 minutes by
 * default; the gate device token lives 30 days and can do far less.
 */
@Component
public class JwtService {

    public static final String ISSUER = "syncgate-api";

    public record Issued(String token, Instant expiresAt) {}

    private final JwtEncoder encoder;
    private final JwtDecoder decoder;
    private final SyncgateProperties props;
    private final AppClock clock;

    private final JdbcClient jdbc;

    public JwtService(SyncgateProperties props, AppClock clock, JdbcClient jdbc) {
        this.jdbc = jdbc;
        this.props = props;
        this.clock = clock;
        SecretKey key = new SecretKeySpec(props.security().jwtSecret().getBytes(StandardCharsets.UTF_8), "HmacSHA256");
        this.encoder = new NimbusJwtEncoder(new ImmutableSecret<>(key));
        NimbusJwtDecoder nimbus = NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
        OAuth2TokenValidator<Jwt> notRevoked = token -> isRevoked(token.getId())
                ? OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token", "token was revoked", null))
                : OAuth2TokenValidatorResult.success();
        nimbus.setJwtValidator(new DelegatingOAuth2TokenValidator<>(
                JwtValidators.createDefaultWithIssuer(ISSUER), notRevoked));
        this.decoder = nimbus;
    }

    public JwtDecoder decoder() {
        return decoder;
    }

    public Issued issue(Role role, String subject, String name) {
        Duration ttl = role == Role.DEVICE ? props.security().deviceTokenTtl() : props.security().adminTokenTtl();
        // Tokens are checked against the real wall clock by the decoder, so
        // they are issued from it as well (the demo clock only drives marks).
        Instant now = Instant.now();
        Instant expires = now.plus(ttl);
        JwtClaimsSet claims = JwtClaimsSet.builder()
                .issuer(ISSUER)
                .id(UUID.randomUUID().toString())
                .subject(subject)
                .issuedAt(now)
                .expiresAt(expires)
                .claim("role", Wire.of(role))
                .claim("name", name)
                .build();
        String token = encoder.encode(
                JwtEncoderParameters.from(JwsHeader.with(MacAlgorithm.HS256).build(), claims)).getTokenValue();
        return new Issued(token, expires);
    }

    /** Ends a token early. It stays on the list only until it would have expired anyway. */
    public void revoke(String jti, Instant expiresAt) {
        if (jti == null || expiresAt == null) {
            return;
        }
        jdbc.sql("DELETE FROM revoked_tokens WHERE expires_at < :now").param("now", Db.ts(Instant.now())).update();
        jdbc.sql("INSERT INTO revoked_tokens (jti, expires_at) SELECT :j, :e "
                        + "WHERE NOT EXISTS (SELECT 1 FROM revoked_tokens WHERE jti = :j)")
                .param("j", jti).param("e", Db.ts(expiresAt)).update();
    }

    boolean isRevoked(String jti) {
        return jti != null && jdbc.sql("SELECT COUNT(*) FROM revoked_tokens WHERE jti = :j").param("j", jti)
                .query(Integer.class).single() > 0;
    }
}
