package in.syncgate.api.backup;

import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.Db;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/** Maps to the Flutter {@code BackupService} and the restore flow. */
@RestController
@RequestMapping("/api/v1/backups")
public class BackupController {

    public record PassphraseRequest(@NotBlank @Size(min = 8, max = 128) String passphrase) {}

    public record BackupDto(String id, Instant createdAt, String destination, String fileName, String sha256,
            long sizeBytes) {}

    private final BackupService backups;

    public BackupController(BackupService backups) {
        this.backups = backups;
    }

    /** Last backup time, for the reminder card on Today and Backup. */
    @GetMapping("/info")
    @PreAuthorize("@caps.can('READ_CORE')")
    public BackupService.BackupInfo info() {
        return backups.info();
    }

    @PutMapping("/passphrase")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('BACKUP_RESTORE')")
    public void passphrase(@Valid @RequestBody PassphraseRequest body) {
        backups.setPassphrase(body.passphrase(), Caller.require().label());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    @PreAuthorize("@caps.can('BACKUP_RESTORE')")
    public BackupDto create() {
        return dto(backups.backupNow(Caller.require().label()));
    }

    @GetMapping
    @PreAuthorize("@caps.can('BACKUP_RESTORE')")
    public List<BackupDto> list() {
        return backups.list().stream().map(BackupController::dto).toList();
    }

    /** The encrypted file itself, for the share sheet / USB / WhatsApp. */
    @GetMapping("/{id}/download")
    @PreAuthorize("@caps.can('BACKUP_RESTORE')")
    public ResponseEntity<byte[]> download(@PathVariable String id) {
        BackupService.BackupRecord record = backups.list().stream()
                .filter(b -> b.id().equals(Db.parseId(id))).findFirst()
                .orElseThrow(() -> ApiException.notFound("Backup"));
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename(record.fileName(), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Sha256", record.sha256())
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .body(backups.download(record.id()));
    }

    /** Restore into a fresh install. Also open during first-run setup. */
    @PostMapping(value = "/restore", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @PreAuthorize("@caps.can('RESTORE_BACKUP')")
    public Map<String, Object> restore(@RequestParam("file") MultipartFile file,
            @RequestParam("passphrase") String passphrase) throws IOException {
        int records = backups.restore(file.getBytes(), passphrase, Caller.require().label());
        return Map.of("restored", true, "records", records, "needsFace", true);
    }

    private static BackupDto dto(BackupService.BackupRecord r) {
        return new BackupDto(r.id().toString(), r.createdAt(), r.destination(), r.fileName(), r.sha256(),
                r.sizeBytes());
    }
}
