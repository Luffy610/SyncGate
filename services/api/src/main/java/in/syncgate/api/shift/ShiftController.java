package in.syncgate.api.shift;

import in.syncgate.api.common.Db;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.List;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Maps to the Flutter {@code ShiftRepository}. */
@RestController
@RequestMapping("/api/v1/shifts")
public class ShiftController {

    public record ShiftDto(String id, @NotBlank @Size(max = 60) String name,
            @Min(0) @Max(1439) int startMinute, @Min(0) @Max(1439) int endMinute,
            @Min(0) @Max(120) int graceMinutes, @Min(1) @Max(7) int weeklyOff) {}

    private final ShiftService shifts;

    public ShiftController(ShiftService shifts) {
        this.shifts = shifts;
    }

    @GetMapping
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<ShiftDto> list() {
        return shifts.all().stream().map(ShiftController::dto).toList();
    }

    @PutMapping("/{id}")
    @PreAuthorize("@caps.can('SHIFT_RULES')")
    public ShiftDto save(@PathVariable String id, @Valid @RequestBody ShiftDto body) {
        var shift = new ShiftService.Shift(Db.parseId(id), body.name().strip(), body.startMinute(),
                body.endMinute(), body.graceMinutes(), body.weeklyOff());
        return dto(shifts.upsert(shift, Caller.require().label()));
    }

    static ShiftDto dto(ShiftService.Shift s) {
        return new ShiftDto(s.id().toString(), s.name(), s.startMinute(), s.endMinute(), s.graceMinutes(),
                s.weeklyOff());
    }
}
