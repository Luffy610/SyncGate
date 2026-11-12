package in.syncgate.api.report;

import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.Db;
import in.syncgate.api.domain.Enums.ExportFormat;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.report.ReportService.Filter;
import in.syncgate.api.security.Caller;
import in.syncgate.api.worker.WorkerController;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.Map;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Reports and exports (maps to the Flutter {@code ReportService}/{@code ExportService}). */
@RestController
@RequestMapping("/api/v1")
public class ReportController {

    public record MusterDto(WorkerController.WorkerDto worker, int present, int absent, int late,
            double overtimeHours, boolean hasOpenExceptions, List<String> days) {}

    public record DailyDto(WorkerController.WorkerDto worker, Instant inAt, Instant outAt, String status,
            boolean flagged) {}

    public record ExportRequest(@NotBlank String format, @NotBlank @Size(max = 7) String month,
            @Size(max = 80) String department, String shiftId, @Size(max = 120) String contractor) {}

    private final ReportService reports;
    private final ExportService exports;

    public ReportController(ReportService reports, ExportService exports) {
        this.reports = reports;
        this.exports = exports;
    }

    @GetMapping("/reports/monthly")
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public List<MusterDto> monthly(@RequestParam String month, @RequestParam(required = false) String department,
            @RequestParam(required = false) String shiftId, @RequestParam(required = false) String contractor) {
        return reports.monthly(filter(month, department, shiftId, contractor)).stream()
                .map(r -> new MusterDto(WorkerController.dto(r.worker()), r.present(), r.absent(), r.late(),
                        r.overtimeHours(), r.hasOpenExceptions(), r.days()))
                .toList();
    }

    @GetMapping("/reports/daily")
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public List<DailyDto> daily(@RequestParam String date) {
        try {
            return reports.daily(LocalDate.parse(date)).stream()
                    .map(r -> new DailyDto(WorkerController.dto(r.worker()), r.inAt(), r.outAt(), r.status(),
                            r.flagged()))
                    .toList();
        } catch (DateTimeParseException e) {
            throw ApiException.invalid("date must be yyyy-MM-dd");
        }
    }

    @GetMapping("/reports/working-days")
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public Map<String, Integer> workingDays(@RequestParam String month) {
        return Map.of("days", reports.workingDays(parseMonth(month)));
    }

    /** Returns the file itself. Row count and checksum travel in headers. */
    @PostMapping("/exports")
    @PreAuthorize("@caps.can('REPORTS_AND_EXPORTS')")
    public ResponseEntity<byte[]> export(@Valid @RequestBody ExportRequest body) {
        ExportFormat format = Wire.parse(ExportFormat.class, body.format());
        ExportService.ExportFile file = exports.export(format,
                filter(body.month(), body.department(), body.shiftId(), body.contractor()),
                Caller.require().label());
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename(file.fileName(), StandardCharsets.UTF_8).build().toString())
                .header("X-Row-Count", Integer.toString(file.rows()))
                .header("X-Content-Sha256", file.sha256())
                .contentType(MediaType.parseMediaType(file.contentType()))
                .body(file.bytes());
    }

    private static Filter filter(String month, String department, String shiftId, String contractor) {
        return new Filter(parseMonth(month), blank(department), shiftId == null || shiftId.isBlank() ? null
                : Db.parseId(shiftId), blank(contractor));
    }

    private static YearMonth parseMonth(String month) {
        try {
            return YearMonth.parse(month);
        } catch (DateTimeParseException e) {
            throw ApiException.invalid("month must be yyyy-MM");
        }
    }

    private static String blank(String text) {
        return text == null || text.isBlank() ? null : text.strip();
    }
}
