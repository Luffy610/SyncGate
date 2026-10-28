package in.syncgate.api.audit;

import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Audit trail endpoints (maps to the Flutter {@code AuditLog} interface). */
@RestController
@RequestMapping("/api/v1/audit")
public class AuditController {

    public record AuditRequest(@NotBlank @Size(max = 80) String actor, @NotBlank @Size(max = 80) String action,
            @Size(max = 500) String detail) {}

    public record AuditDto(Instant at, String actor, String action, String detail) {}

    private final AuditService audit;

    public AuditController(AuditService audit) {
        this.audit = audit;
    }

    /**
     * The app reports admin actions it performed. The server stamps its own
     * time and the verified role, so a client cannot back-date or disguise an
     * entry; the actor label it sends is kept for display only.
     */
    @PostMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('AUDIT_WRITE')")
    public void append(@Valid @RequestBody AuditRequest request) {
        Caller caller = Caller.require();
        audit.record(request.actor(), request.action(),
                "[" + Wire.of(caller.role()) + "] " + (request.detail() == null ? "" : request.detail()));
    }

    @GetMapping
    @PreAuthorize("@caps.can('AUDIT_READ')")
    public List<AuditDto> latest(@RequestParam(defaultValue = "200") int limit) {
        return audit.latest(limit).stream()
                .map(e -> new AuditDto(e.at(), e.actor(), e.action(), e.detail()))
                .toList();
    }

    @GetMapping("/verify")
    @PreAuthorize("@caps.can('AUDIT_READ')")
    public AuditService.Verification verify() {
        return audit.verify();
    }
}
