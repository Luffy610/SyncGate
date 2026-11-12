package in.syncgate.api.user;

import in.syncgate.api.common.Db;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Pattern;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.GetMapping;

/** Owner-only user administration (Settings > Users and PINs). */
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

    public record PinRequest(@Pattern(regexp = "^[0-9]{6}$", message = "PIN must be 6 digits") String pin) {}

    private final UserService users;

    public UserController(UserService users) {
        this.users = users;
    }

    @GetMapping
    @PreAuthorize("@caps.can('LICENCE_AND_USERS')")
    public List<AuthController.UserDto> list() {
        return users.users().stream()
                .map(u -> new AuthController.UserDto(u.id().toString(), u.name(), Wire.of(u.role())))
                .toList();
    }

    @PutMapping("/{id}/pin")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('LICENCE_AND_USERS')")
    public void setPin(@PathVariable String id, @Valid @RequestBody PinRequest request) {
        users.setPin(Db.parseId(id), request.pin(), Caller.require().label());
    }
}
