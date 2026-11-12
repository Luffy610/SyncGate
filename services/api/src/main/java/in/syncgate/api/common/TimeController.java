package in.syncgate.api.common;

import java.time.Instant;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The server's time. The app reads it once at start-up and shows server time,
 * because attendance is stamped by the server, not the phone (ADR-0012).
 */
@RestController
@RequestMapping("/api/v1/time")
public class TimeController {

    private final AppClock clock;

    public TimeController(AppClock clock) {
        this.clock = clock;
    }

    @GetMapping
    @PreAuthorize("@caps.can('READ_CORE')")
    public Map<String, Instant> now() {
        return Map.of("now", clock.now());
    }
}
