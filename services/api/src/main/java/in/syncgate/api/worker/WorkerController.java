package in.syncgate.api.worker;

import in.syncgate.api.common.Db;
import in.syncgate.api.domain.Enums.FaceStatus;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** Maps to the Flutter {@code WorkerRepository} and {@code ConsentRepository}. */
@RestController
@RequestMapping("/api/v1")
public class WorkerController {

    public record WorkerDto(String id, String code, String name, LocalDate dateOfBirth, String department,
            String designation, String shiftId, String contractor, String phone, String language,
            String faceStatus, boolean active, boolean onLeave) {}

    public record WorkerRequest(String id, @NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 120) String name,
            @NotNull LocalDate dateOfBirth, @NotBlank @Size(max = 80) String department,
            @NotBlank @Size(max = 80) String designation, @NotBlank String shiftId, @Size(max = 120) String contractor,
            @Size(max = 20) String phone, @NotBlank @Size(max = 5) String language) {}

    public record FaceStatusRequest(@NotBlank String status) {}

    public record ActiveRequest(boolean active) {}

    public record DepartmentRequest(@NotBlank @Size(max = 80) String name) {}

    public record ConsentRequest(@NotBlank String workerId, @NotBlank @Size(max = 40) String noticeVersion,
            @NotBlank @Size(max = 5) String language, @NotBlank @Size(max = 80) String adminId) {}

    private final WorkerService workers;

    public WorkerController(WorkerService workers) {
        this.workers = workers;
    }

    @GetMapping("/workers")
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<WorkerDto> list() {
        return workers.all().stream().map(WorkerController::dto).toList();
    }

    @GetMapping("/workers/next-code")
    @PreAuthorize("@caps.can('READ_CORE')")
    public Map<String, String> nextCode() {
        return Map.of("code", workers.nextCode());
    }

    @GetMapping("/workers/code-unique")
    @PreAuthorize("@caps.can('READ_CORE')")
    public Map<String, Boolean> codeUnique(@RequestParam String code,
            @RequestParam(required = false) String exceptWorkerId) {
        UUID except = exceptWorkerId == null || exceptWorkerId.isBlank() ? null : Db.parseId(exceptWorkerId);
        return Map.of("unique", workers.isCodeUnique(code.strip(), except));
    }

    @GetMapping("/workers/{id}")
    @PreAuthorize("@caps.can('READ_CORE')")
    public WorkerDto get(@PathVariable String id) {
        return dto(workers.require(Db.parseId(id)));
    }

    @PostMapping("/workers")
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("@caps.can('ENROL_WORKERS')")
    public WorkerDto add(@Valid @RequestBody WorkerRequest body) {
        return dto(workers.add(request(body), Caller.require().label()));
    }

    @PutMapping("/workers/{id}")
    @PreAuthorize("@caps.can('ENROL_WORKERS')")
    public WorkerDto update(@PathVariable String id, @Valid @RequestBody WorkerRequest body) {
        return dto(workers.update(Db.parseId(id), request(body), Caller.require().label()));
    }

    @PutMapping("/workers/{id}/face-status")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('ENROL_WORKERS')")
    public void faceStatus(@PathVariable String id, @Valid @RequestBody FaceStatusRequest body) {
        workers.setFaceStatus(Db.parseId(id), Wire.parse(FaceStatus.class, body.status()), Caller.require().label());
    }

    @PutMapping("/workers/{id}/active")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('ENROL_WORKERS')")
    public void active(@PathVariable String id, @RequestBody ActiveRequest body) {
        workers.setActive(Db.parseId(id), body.active(), Caller.require().label());
    }

    @DeleteMapping("/workers/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('DELETE_WORKER')")
    public void delete(@PathVariable String id) {
        workers.delete(Db.parseId(id), Caller.require().label());
    }

    @GetMapping("/departments")
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<String> departments() {
        return workers.departments();
    }

    @PostMapping("/departments")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('ENROL_WORKERS')")
    public void addDepartment(@Valid @RequestBody DepartmentRequest body) {
        workers.addDepartment(body.name(), Caller.require().label());
    }

    @GetMapping("/contractors")
    @PreAuthorize("@caps.can('READ_CORE')")
    public List<String> contractors() {
        return workers.contractors();
    }

    @PostMapping("/consents")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('ENROL_WORKERS')")
    public void consent(@Valid @RequestBody ConsentRequest body) {
        workers.recordConsent(Db.parseId(body.workerId()), body.noticeVersion(), body.language(), body.adminId(),
                Caller.require().label());
    }

    @GetMapping("/consents/{workerId}")
    @PreAuthorize("@caps.can('READ_CORE')")
    public Map<String, Boolean> hasConsent(@PathVariable String workerId) {
        return Map.of("hasConsent", workers.hasConsent(Db.parseId(workerId)));
    }

    private static WorkerService.NewWorker request(WorkerRequest b) {
        UUID id = b.id() == null || b.id().isBlank() ? null : Db.parseId(b.id());
        return new WorkerService.NewWorker(id, b.code(), b.name(), b.dateOfBirth(), b.department(), b.designation(),
                Db.parseId(b.shiftId()), b.contractor(), b.phone(), b.language());
    }

    public static WorkerDto dto(WorkerService.Worker w) {
        return new WorkerDto(w.id().toString(), w.code(), w.name(), w.dateOfBirth(), w.department(), w.designation(),
                w.shiftId().toString(), w.contractor(), w.phone(), w.language(), Wire.of(w.faceStatus()), w.active(),
                w.onLeave());
    }
}
