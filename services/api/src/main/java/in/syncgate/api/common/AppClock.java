package in.syncgate.api.common;

import in.syncgate.api.config.SyncgateProperties;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import org.springframework.stereotype.Component;

/**
 * The server's single source of time. Marks use this clock, never the
 * client's, so changing a phone's clock cannot forge attendance (ADR-0012).
 * With {@code syncgate.clock.start} set (dev only) it begins at that instant
 * and then runs in real time, matching the Flutter demo clock.
 */
public interface AppClock {

    Instant now();

    ZoneId zone();

    default LocalDate today() {
        return now().atZone(zone()).toLocalDate();
    }

    /** Instants are stored and hashed at millisecond precision. */
    static Instant millis(Instant instant) {
        return instant.truncatedTo(ChronoUnit.MILLIS);
    }

    @Component
    class Default implements AppClock {
        private final ZoneId zone;
        private final Instant base;
        private final long startedNanos = System.nanoTime();

        public Default(SyncgateProperties props) {
            this.zone = ZoneId.of(props.zone());
            String start = props.clock().start();
            this.base = start == null || start.isBlank() ? null : OffsetDateTime.parse(start).toInstant();
        }

        @Override
        public Instant now() {
            if (base == null) {
                return millis(Instant.now());
            }
            return millis(base.plusNanos(System.nanoTime() - startedNanos));
        }

        @Override
        public ZoneId zone() {
            return zone;
        }
    }
}
