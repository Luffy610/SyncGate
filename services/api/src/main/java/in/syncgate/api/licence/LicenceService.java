package in.syncgate.api.licence;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import in.syncgate.api.config.SyncgateProperties;
import in.syncgate.api.domain.Enums.LicenceState;
import in.syncgate.api.domain.Wire;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.Base64;
import java.util.regex.Pattern;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters;
import org.bouncycastle.crypto.params.Ed25519PublicKeyParameters;
import org.bouncycastle.crypto.signers.Ed25519Signer;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Licence state (ADR-0014): one licence per install, annual, never blocking
 * export, backup or worker-rights functions. The effective state is computed
 * from dates every time it is read, so it needs no scheduler.
 *
 * <p>Activation here is a stand-in for the separate licence server: in
 * {@code mock} mode any well-formed key activates; otherwise the key must be
 * in {@code issued_licence_keys}. The signed token (Ed25519) is real, so the
 * app can later verify it offline.
 */
@Service
public class LicenceService {

    private static final Pattern KEY = Pattern.compile("^SGT-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$");

    public record Status(LicenceState state, LocalDate expiresOn, String key) {}

    private final JdbcClient jdbc;
    private final AppClock clock;
    private final SyncgateProperties props;
    private final AuditService audit;
    private final Ed25519PrivateKeyParameters signingKey;

    public LicenceService(JdbcClient jdbc, AppClock clock, SyncgateProperties props, AuditService audit) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.props = props;
        this.audit = audit;
        this.signingKey = new Ed25519PrivateKeyParameters(seed(props));
    }

    public Status current() {
        var row = jdbc.sql("SELECT state, licence_key, expires_on, trial_started FROM licence WHERE id = 1")
                .query((rs, i) -> new Object[] {rs.getString(1), rs.getString(2),
                    rs.getObject(3, LocalDate.class), rs.getObject(4, LocalDate.class)})
                .optional();
        if (row.isEmpty()) {
            return new Status(LicenceState.NONE, null, null);
        }
        LicenceState stored = Wire.parse(LicenceState.class, (String) row.get()[0]);
        String key = (String) row.get()[1];
        LocalDate expires = (LocalDate) row.get()[2];
        LocalDate trialStarted = (LocalDate) row.get()[3];
        LocalDate today = clock.today();
        switch (stored) {
            case TRIAL: {
                LocalDate trialEnds = trialStarted.plusDays(props.licence().trialDays());
                return new Status(today.isAfter(trialEnds) ? LicenceState.RESTRICTED : LicenceState.TRIAL, trialEnds,
                        null);
            }
            case ACTIVE: {
                if (!today.isAfter(expires)) {
                    return new Status(LicenceState.ACTIVE, expires, key);
                }
                boolean inGrace = !today.isAfter(expires.plusDays(props.licence().graceDays()));
                return new Status(inGrace ? LicenceState.GRACE_OVERDUE : LicenceState.RESTRICTED, expires, key);
            }
            default:
                return new Status(stored, expires, key);
        }
    }

    @Transactional
    public Status activate(String rawKey, String actor) {
        String key = rawKey == null ? "" : rawKey.strip().toUpperCase();
        if (!KEY.matcher(key).matches()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "INVALID_LICENCE_KEY", "That key is not valid");
        }
        if (props.licence().mock()) {
            // Demo switch carried over from the Flutter fakes: a key containing NONET behaves as offline.
            if (key.replace("-", "").contains("NONET")) {
                throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "NO_INTERNET", "Could not reach the licence server");
            }
        } else {
            int updated = jdbc.sql("UPDATE issued_licence_keys SET activated_at = :now "
                            + "WHERE licence_key = :k AND revoked = FALSE")
                    .param("k", key).param("now", Db.ts(clock.now())).update();
            if (updated == 0) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "INVALID_LICENCE_KEY", "That key is not valid");
            }
        }
        LocalDate expires = clock.today().plusDays(props.licence().validityDays());
        jdbc.sql("DELETE FROM licence").update();
        jdbc.sql("INSERT INTO licence (id, state, licence_key, expires_on, last_checkin, token) "
                        + "VALUES (1, 'active', :k, :e, :now, :t)")
                .param("k", key).param("e", expires).param("now", Db.ts(clock.now())).param("t", token(key, expires))
                .update();
        audit.record(actor, "licence.activated", key.substring(0, 8) + "…");
        return current();
    }

    @Transactional
    public Status startTrial(String actor) {
        if (current().state() != LicenceState.NONE) {
            return current();
        }
        jdbc.sql("DELETE FROM licence").update();
        jdbc.sql("INSERT INTO licence (id, state, trial_started) VALUES (1, 'trial', :d)")
                .param("d", clock.today()).update();
        audit.record(actor, "licence.trial_started", null);
        return current();
    }

    /** Refreshes the check-in time and re-signs the token. */
    @Transactional
    public Status checkIn(String actor) {
        Status status = current();
        if (status.state() != LicenceState.ACTIVE && status.state() != LicenceState.GRACE_OVERDUE) {
            return status;
        }
        jdbc.sql("UPDATE licence SET last_checkin = :now, token = :t WHERE id = 1")
                .param("now", Db.ts(clock.now())).param("t", token(status.key(), status.expiresOn())).update();
        return current();
    }

    /** {@code v1.<payload>.<signature>}, both base64url. Payload is small, signed JSON. */
    String token(String key, LocalDate expires) {
        String payload = "{\"lic\":\"" + sha256Short(key) + "\",\"iat\":\"" + clock.now() + "\",\"exp\":\"" + expires
                + "\"}";
        byte[] bytes = payload.getBytes(StandardCharsets.UTF_8);
        Ed25519Signer signer = new Ed25519Signer();
        signer.init(true, signingKey);
        signer.update(bytes, 0, bytes.length);
        Base64.Encoder enc = Base64.getUrlEncoder().withoutPadding();
        return "v1." + enc.encodeToString(bytes) + "." + enc.encodeToString(signer.generateSignature());
    }

    /** Verifies a token this server issued. The app does the same offline with the public key. */
    public boolean verify(String token) {
        String[] parts = token == null ? new String[0] : token.split("\\.");
        if (parts.length != 3 || !parts[0].equals("v1")) {
            return false;
        }
        try {
            byte[] payload = Base64.getUrlDecoder().decode(parts[1]);
            byte[] signature = Base64.getUrlDecoder().decode(parts[2]);
            Ed25519Signer signer = new Ed25519Signer();
            signer.init(false, new Ed25519PublicKeyParameters(publicKey(), 0));
            signer.update(payload, 0, payload.length);
            return signer.verifySignature(signature);
        } catch (IllegalArgumentException e) {
            return false;
        }
    }

    public byte[] publicKey() {
        return signingKey.generatePublicKey().getEncoded();
    }

    String storedToken() {
        return jdbc.sql("SELECT token FROM licence WHERE id = 1").query(String.class).optional().orElse(null);
    }

    private static byte[] seed(SyncgateProperties props) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(Base64.getDecoder().decode(props.security().masterKey()), "HmacSHA256"));
            return mac.doFinal("syncgate-licence-signing-v1".getBytes(StandardCharsets.UTF_8));
        } catch (java.security.GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    private static String sha256Short(String text) {
        try {
            byte[] digest = java.security.MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(digest).substring(0, 16);
        } catch (java.security.NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
