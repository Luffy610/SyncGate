package in.syncgate.api.attendance;

import in.syncgate.api.attendance.ExceptionService.ExceptionRecord;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.Db;
import in.syncgate.api.domain.Enums.ExceptionKind;
import in.syncgate.api.domain.Enums.ManualReason;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Maps to the Flutter {@code ExceptionRepository}. */
@RestController
@RequestMapping("/api/v1/exceptions")
public class ExceptionController {

    public record ExceptionDto(String id, String kind, Instant at, String workerId, boolean resolved, String eventId,
            String actor, String reason, Instant inAt, Integer minutes, Integer count) {}

    public record ExceptionRequest(String id, @NotBlank String kind, String workerId, String eventId, String actor,
            Instant inAt, @Min(0) @Max(100000) Integer minutes, @Min(0) @Max(100000) Integer count) {}

    private final ExceptionService exceptions;

    public ExceptionController(ExceptionService exceptions) {
        this.exceptions = exceptions;
    }

    @GetMapping
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<ExceptionDto> list() {
        return exceptions.all().stream().map(ExceptionController::dto).toList();
    }

    /**
     * Records exceptions the phone detected itself (clock change, duplicate
     * face, spoof suspect). Manual-entry, low-margin and missing-OUT
     * exceptions are created by the server and refused here.
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("@caps.can('MARK_FACE')")
    public ExceptionDto add(@Valid @RequestBody ExceptionRequest body) {
        ExceptionKind kind = Wire.parse(ExceptionKind.class, body.kind());
        if (kind == ExceptionKind.MANUAL || kind == ExceptionKind.MISSING_OUT || kind == ExceptionKind.LOW_MARGIN) {
            throw ApiException.invalid("The server records that kind itself");
        }
        UUID id = body.id() == null || body.id().isBlank() ? null : Db.parseId(body.id());
        UUID worker = body.workerId() == null || body.workerId().isBlank() ? null : Db.parseId(body.workerId());
        UUID event = body.eventId() == null || body.eventId().isBlank() ? null : Db.parseId(body.eventId());
        return dto(exceptions.add(new ExceptionRecord(id, kind, null, worker, false, event, body.actor(), null,
                body.inAt(), body.minutes(), body.count())));
    }

    @PostMapping("/{id}/resolve")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('CORRECTIONS')")
    public void resolve(@PathVariable String id) {
        exceptions.resolve(Db.parseId(id), Caller.require().label());
    }

    static ExceptionDto dto(ExceptionRecord e) {
        ManualReason reason = e.reason();
        return new ExceptionDto(e.id().toString(), Wire.of(e.kind()), e.at(),
                e.workerId() == null ? null : e.workerId().toString(), e.resolved(),
                e.eventId() == null ? null : e.eventId().toString(), e.actor(),
                reason == null ? null : Wire.of(reason), e.inAt(), e.minutes(), e.count());
    }
}
