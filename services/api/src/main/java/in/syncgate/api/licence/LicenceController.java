package in.syncgate.api.licence;

import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Maps to the Flutter {@code LicenceService}. Licence state never blocks export or backup. */
@RestController
@RequestMapping("/api/v1/licence")
public class LicenceController {

    public record LicenceDto(String state, LocalDate expiresOn, String key) {}

    public record ActivateRequest(@NotBlank @Size(max = 30) String key) {}

    private final LicenceService licence;

    public LicenceController(LicenceService licence) {
        this.licence = licence;
    }

    @GetMapping
    @PreAuthorize("@caps.can('LICENCE_READ')")
    public LicenceDto get() {
        return dto(licence.current());
    }

    @PostMapping("/activate")
    @PreAuthorize("@caps.can('LICENCE_AND_USERS')")
    public LicenceDto activate(@Valid @RequestBody ActivateRequest body) {
        return dto(licence.activate(body.key(), Caller.require().label()));
    }

    @PostMapping("/trial")
    @PreAuthorize("@caps.can('LICENCE_AND_USERS')")
    public LicenceDto trial() {
        return dto(licence.startTrial(Caller.require().label()));
    }

    @PostMapping("/checkin")
    @PreAuthorize("@caps.can('LICENCE_AND_USERS')")
    public LicenceDto checkIn() {
        return dto(licence.checkIn(Caller.require().label()));
    }

    private static LicenceDto dto(LicenceService.Status s) {
        return new LicenceDto(Wire.of(s.state()), s.expiresOn(), s.key());
    }
}
