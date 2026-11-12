package in.syncgate.api.security;

import com.nimbusds.jose.jwk.source.ImmutableSecret;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.config.SyncgateProperties;
import in.syncgate.api.domain.Role;
import in.syncgate.api.domain.Wire;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import javax.crypto.SecretKey;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
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

    public JwtService(SyncgateProperties props, AppClock clock) {
        this.props = props;
        this.clock = clock;
        SecretKey key = new SecretKeySpec(props.security().jwtSecret().getBytes(StandardCharsets.UTF_8), "HmacSHA256");
        this.encoder = new NimbusJwtEncoder(new ImmutableSecret<>(key));
        NimbusJwtDecoder nimbus = NimbusJwtDecoder.withSecretKey(key).macAlgorithm(MacAlgorithm.HS256).build();
        nimbus.setJwtValidator(JwtValidators.createDefaultWithIssuer(ISSUER));
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
}
