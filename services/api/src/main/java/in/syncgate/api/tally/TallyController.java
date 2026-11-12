package in.syncgate.api.tally;

import in.syncgate.api.common.Db;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Maps to the Flutter {@code TallyMappingRepository} and {@code ExportService.tallyMatch}. */
@RestController
@RequestMapping("/api/v1/tally")
public class TallyController {

    public record NameRequest(@NotBlank @Size(max = 120) String name) {}

    private final TallyService tally;

    public TallyController(TallyService tally) {
        this.tally = tally;
    }

    /** Worker id to Tally employee name, for mapped workers only. */
    @GetMapping("/mappings")
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public Map<String, String> mappings() {
        Map<String, String> out = new LinkedHashMap<>();
        tally.mappings().forEach((id, name) -> out.put(id.toString(), name));
        return out;
    }

    @PutMapping("/mappings/{workerId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public void set(@PathVariable String workerId, @Valid @RequestBody NameRequest body) {
        tally.set(Db.parseId(workerId), body.name(), Caller.require().label());
    }

    @GetMapping("/match")
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public TallyService.Match match() {
        return tally.match();
    }
}
