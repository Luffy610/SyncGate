package in.syncgate.api.attendance;

import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.Db;
import in.syncgate.api.domain.Enums.Direction;
import in.syncgate.api.domain.Enums.ManualReason;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Maps to the Flutter {@code AttendanceRepository} and the gate use cases. */
@RestController
@RequestMapping("/api/v1/attendance")
public class AttendanceController {

    public record EventDto(String id, String workerId, Instant at, String direction, String method, String reason,
            String markedBy, boolean onTime) {}

    public record FaceMarkRequest(String id, @NotBlank String workerId,
            @DecimalMin("0.0") @DecimalMax("1.0") double score,
            @DecimalMin("0.0") @DecimalMax("1.0") double margin,
            @DecimalMin("0.0") @DecimalMax("1.0") double liveness) {}

    public record ManualMarkRequest(String id, @NotBlank String workerId, @NotBlank String reason,
            @Size(max = 40) String markedBy) {}

    public record CorrectionRequest(String id, @NotBlank String workerId, @NotNull Instant at,
            @NotBlank String direction, @NotBlank @Size(max = 200) String reason, String exceptionId,
            @Size(max = 40) String markedBy) {}

    private final AttendanceService attendance;

    public AttendanceController(AttendanceService attendance) {
        this.attendance = attendance;
    }

    /** Reported by the on-device matcher; the server applies cooldown and direction. */
    @PostMapping("/face-marks")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("@caps.can('MARK_FACE')")
    public EventDto faceMark(@Valid @RequestBody FaceMarkRequest body) {
        return dto(attendance.markFace(optionalId(body.id()), Db.parseId(body.workerId()), body.score(),
                body.margin(), body.liveness()));
    }

    @PostMapping("/manual-marks")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("@caps.can('MANUAL_ENTRY')")
    public EventDto manualMark(@Valid @RequestBody ManualMarkRequest body) {
        String actor = body.markedBy() == null || body.markedBy().isBlank() ? Caller.require().label()
                : body.markedBy().strip();
        return dto(attendance.markManual(optionalId(body.id()), Db.parseId(body.workerId()),
                Wire.parse(ManualReason.class, body.reason()), actor));
    }

    @PostMapping("/corrections")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("@caps.can('CORRECTIONS')")
    public EventDto correction(@Valid @RequestBody CorrectionRequest body) {
        String actor = body.markedBy() == null || body.markedBy().isBlank() ? Caller.require().label()
                : body.markedBy().strip();
        UUID exception = body.exceptionId() == null || body.exceptionId().isBlank() ? null
                : Db.parseId(body.exceptionId());
        return dto(attendance.correct(optionalId(body.id()), Db.parseId(body.workerId()), body.at(),
                Wire.parse(Direction.class, body.direction()), body.reason(), actor, exception));
    }

    @GetMapping("/day")
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<EventDto> day(@RequestParam String date) {
        return attendance.forDay(parseDate(date)).stream().map(AttendanceController::dto).toList();
    }

    @GetMapping("/events")
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<EventDto> events(@RequestParam String from, @RequestParam String to) {
        try {
            return attendance.between(Instant.parse(from), Instant.parse(to)).stream()
                    .map(AttendanceController::dto).toList();
        } catch (DateTimeParseException e) {
            throw ApiException.invalid("from and to must be ISO-8601 instants");
        }
    }

    @GetMapping("/last")
    @PreAuthorize("@caps.can('READ_CORE')")
    public ResponseEntity<EventDto> last(@RequestParam String workerId) {
        return attendance.lastEvent(Db.parseId(workerId))
                .map(e -> ResponseEntity.ok(dto(e)))
                .orElseGet(() -> ResponseEntity.noContent().build());
    }

    @GetMapping("/verify")
    @PreAuthorize("@caps.can('AUDIT_READ')")
    public AttendanceService.Verification verify() {
        return attendance.verify();
    }

    static EventDto dto(AttendanceService.Event e) {
        return new EventDto(e.id().toString(), e.workerId().toString(), e.at(), Wire.of(e.direction()),
                Wire.of(e.method()), e.reason(), e.markedBy(), e.onTime());
    }

    private static UUID optionalId(String id) {
        return id == null || id.isBlank() ? null : Db.parseId(id);
    }

    private static LocalDate parseDate(String text) {
        try {
            return LocalDate.parse(text);
        } catch (DateTimeParseException e) {
            throw ApiException.invalid("date must be yyyy-MM-dd");
        }
    }
}
