package in.syncgate.api.user;

import in.syncgate.api.common.ApiException;
import in.syncgate.api.config.SyncgateProperties;
import in.syncgate.api.domain.Role;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.JwtService;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Sign-in family: device key, PIN login, owner creation and PIN reset. */
@RestController
@RequestMapping("/api/v1")
public class AuthController {

    private static final String PIN = "^[0-9]{6}$";

    public record DeviceRequest(@NotBlank @Size(max = 200) String deviceKey) {}

    public record LoginRequest(@NotBlank String role, @Pattern(regexp = PIN, message = "PIN must be 6 digits") String pin) {}

    public record OwnerRequest(@Pattern(regexp = PIN, message = "PIN must be 6 digits") String pin) {}

    public record ResetRequest(@NotBlank @Size(max = 40) String recoveryCode,
            @Pattern(regexp = PIN, message = "PIN must be 6 digits") String newPin) {}

    public record UserDto(String id, String name, String role) {}

    public record TokenResponse(String token, Instant expiresAt, UserDto user, String recoveryCode) {}

    public record SetupStatus(boolean hasOwner) {}

    private final UserService users;
    private final JwtService jwt;
    private final SyncgateProperties props;

    public AuthController(UserService users, JwtService jwt, SyncgateProperties props) {
        this.users = users;
        this.jwt = jwt;
        this.props = props;
    }

    @GetMapping("/setup/status")
    public SetupStatus status() {
        return new SetupStatus(users.ownerExists());
    }

    /** The gate phone proves it holds a configured device key. */
    @PostMapping("/auth/device")
    public TokenResponse device(@Valid @RequestBody DeviceRequest request) {
        boolean known = false;
        for (String key : props.security().deviceKeys()) {
            known |= constantTimeEquals(key, request.deviceKey());
        }
        if (!known) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "UNAUTHENTICATED", "Unknown device");
        }
        JwtService.Issued issued = jwt.issue(Role.DEVICE, "device", "Gate device");
        return new TokenResponse(issued.token(), issued.expiresAt(), null, null);
    }

    /** Ends the caller's own token now (Admin returns to the gate), instead of waiting for it to expire. */
    @PostMapping("/auth/logout")
    @org.springframework.web.bind.annotation.ResponseStatus(HttpStatus.NO_CONTENT)
    public void logout(@AuthenticationPrincipal Jwt token) {
        if (token != null) {
            jwt.revoke(token.getId(), token.getExpiresAt());
        }
    }

    @PostMapping("/auth/login")
    public TokenResponse login(@Valid @RequestBody LoginRequest request) {
        Role role = Wire.parse(Role.class, request.role());
        return answer(users.verifyPin(role, request.pin()), null);
    }

    /** Only works while no owner exists. Returns the recovery code once. */
    @PostMapping("/auth/owner")
    public TokenResponse createOwner(@Valid @RequestBody OwnerRequest request) {
        String recovery = users.createOwner(request.pin());
        UserService.AppUser owner = users.ownerUser();
        JwtService.Issued issued = jwt.issue(Role.OWNER, owner.id().toString(), owner.name());
        return new TokenResponse(issued.token(), issued.expiresAt(), dto(owner), recovery);
    }

    @PostMapping("/auth/reset-owner-pin")
    public TokenResponse reset(@Valid @RequestBody ResetRequest request) {
        return answer(users.resetOwnerPin(request.recoveryCode(), request.newPin()), null);
    }

    private TokenResponse answer(UserService.PinResult result, String recovery) {
        if (result instanceof UserService.PinResult.Ok ok) {
            JwtService.Issued issued = jwt.issue(ok.user().role(), ok.user().id().toString(), ok.user().name());
            return new TokenResponse(issued.token(), issued.expiresAt(), dto(ok.user()), recovery);
        }
        if (result instanceof UserService.PinResult.Locked locked) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "LOCKED_OUT", "Too many wrong attempts",
                    Map.of("retryAfterSeconds", Math.max(1, locked.remaining().toSeconds())));
        }
        UserService.PinResult.Wrong wrong = (UserService.PinResult.Wrong) result;
        throw new ApiException(HttpStatus.UNAUTHORIZED, "WRONG_PIN", "Wrong PIN",
                Map.of("attemptsLeft", wrong.attemptsLeft(),
                        "lockedForSeconds", wrong.lockedFor() == null ? 0 : wrong.lockedFor().toSeconds()));
    }

    private static UserDto dto(UserService.AppUser user) {
        return new UserDto(user.id().toString(), user.name(), Wire.of(user.role()));
    }

    private static boolean constantTimeEquals(String a, String b) {
        try {
            MessageDigest sha = MessageDigest.getInstance("SHA-256");
            return MessageDigest.isEqual(sha.digest(a.getBytes(StandardCharsets.UTF_8)),
                    sha.digest(b.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
