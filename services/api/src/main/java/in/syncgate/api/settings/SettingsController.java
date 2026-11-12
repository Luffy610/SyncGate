package in.syncgate.api.settings;

import in.syncgate.api.domain.Capability;
import in.syncgate.api.security.Caller;
import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/** App settings (maps to the Flutter {@code SettingsRepository}). */
@RestController
@RequestMapping("/api/v1/settings")
public class SettingsController {

    public record SettingsDto(
            @NotBlank String mode,
            @Min(1) @Max(20) int setupStep,
            @NotBlank @Size(max = 5) String language,
            @Min(1) @Max(10) int idleMinutes,
            @Min(60) @Max(600) int cooldownSeconds,
            @DecimalMin("0.0") @DecimalMax("1.0") double voiceVolume,
            boolean screenFillLight,
            boolean use24HourClock,
            @Min(1) @Max(60) int remindBackupDays,
            boolean autoBackup,
            @NotBlank @Size(max = 40) String gateOperatorId,
            boolean biometricEnabled,
            boolean backupPassphraseSet) {}

    private final SettingsService settings;

    public SettingsController(SettingsService settings) {
        this.settings = settings;
    }

    @GetMapping
    @PreAuthorize("@caps.can('READ_CORE')")
    public SettingsDto get() {
        return settings.load();
    }

    /**
     * The gate phone (and a gate operator) may only move between setup, gate
     * and admin mode; every other field needs the settings capability. The
     * backup-passphrase flag is owned by the backup service and ignored here.
     */
    @PutMapping
    @ResponseStatus(HttpStatus.NO_CONTENT)
    @PreAuthorize("@caps.can('SETTINGS_MODE')")
    public void save(@Valid @RequestBody SettingsDto request) {
        Caller caller = Caller.require();
        boolean full = Capability.granted(caller.role(), Capability.SETTINGS_WRITE);
        settings.save(request, full, caller.label());
    }
}
