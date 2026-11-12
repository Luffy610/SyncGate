package in.syncgate.api.attendance;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import in.syncgate.api.domain.Enums.ExceptionKind;
import in.syncgate.api.domain.Enums.ManualReason;
import in.syncgate.api.domain.Wire;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Things an admin should review before payroll (FR-RPT-06). */
@Service
public class ExceptionService {

    public record ExceptionRecord(UUID id, ExceptionKind kind, Instant at, UUID workerId, boolean resolved,
            UUID eventId, String actor, ManualReason reason, Instant inAt, Integer minutes, Integer count) {}

    private static final String COLUMNS =
            "id, kind, at, worker_id, resolved, event_id, actor, reason, in_at, minutes, event_count";

    private final JdbcClient jdbc;
    private final AppClock clock;
    private final AuditService audit;

    public ExceptionService(JdbcClient jdbc, AppClock clock, AuditService audit) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.audit = audit;
    }

    public List<ExceptionRecord> all() {
        detectMissingOut();
        return jdbc.sql("SELECT " + COLUMNS + " FROM exceptions ORDER BY resolved, at DESC")
                .query((rs, i) -> map(rs)).list();
    }

    @Transactional
    public ExceptionRecord add(ExceptionRecord in) {
        UUID id = in.id() == null ? Uuid7.next() : in.id();
        if (jdbc.sql("SELECT COUNT(*) FROM exceptions WHERE id = :id").param("id", id).query(Integer.class).single() > 0) {
            return get(id);
        }
        jdbc.sql("""
                INSERT INTO exceptions (id, kind, at, worker_id, resolved, event_id, actor, reason, in_at, minutes,
                    event_count) VALUES (:id, :kind, :at, :w, FALSE, :ev, :actor, :reason, :inAt, :min, :cnt)""")
                .param("id", id).param("kind", Wire.of(in.kind())).param("at", Db.ts(clock.now()))
                .param("w", in.workerId()).param("ev", in.eventId()).param("actor", in.actor())
                .param("reason", in.reason() == null ? null : Wire.of(in.reason())).param("inAt", Db.ts(in.inAt()))
                .param("min", in.minutes()).param("cnt", in.count()).update();
        return get(id);
    }

    @Transactional
    public void resolve(UUID id, String actor) {
        ExceptionRecord record = get(id);
        if (record.resolved()) {
            return;
        }
        jdbc.sql("UPDATE exceptions SET resolved = TRUE WHERE id = :id").param("id", id).update();
        audit.record(actor, "exception.reviewed", Wire.of(record.kind()));
    }

    public ExceptionRecord get(UUID id) {
        return jdbc.sql("SELECT " + COLUMNS + " FROM exceptions WHERE id = :id").param("id", id)
                .query((rs, i) -> map(rs)).optional().orElseThrow(() -> ApiException.notFound("Exception"));
    }

    /**
     * An IN on an earlier day with no OUT that day becomes a "missing OUT"
     * exception (FR-SHF-06), once per IN event. Today is excluded: the worker
     * may still be on shift.
     */
    @Scheduled(fixedDelayString = "PT15M", initialDelayString = "PT1M")
    @Transactional
    public void detectMissingOut() {
        LocalDate today = clock.today();
        Instant startOfToday = today.atStartOfDay(clock.zone()).toInstant();
        var lastIns = jdbc.sql("""
                SELECT e.id, e.worker_id, e.at FROM attendance_events e
                WHERE e.direction = 'checkIn' AND e.at < :today
                  AND NOT EXISTS (SELECT 1 FROM exceptions x WHERE x.event_id = e.id AND x.kind = 'missingOut')""")
                .param("today", Db.ts(startOfToday))
                .query((rs, i) -> new Object[] {Db.uuid(rs, "id"), Db.uuid(rs, "worker_id"), Db.instant(rs, "at")})
                .list();
        for (Object[] row : lastIns) {
            UUID eventId = (UUID) row[0];
            UUID workerId = (UUID) row[1];
            Instant inAt = (Instant) row[2];
            LocalDate day = inAt.atZone(clock.zone()).toLocalDate();
            Instant from = day.atStartOfDay(clock.zone()).toInstant();
            Instant to = day.plusDays(1).atStartOfDay(clock.zone()).toInstant();
            boolean hasOut = jdbc.sql("""
                    SELECT COUNT(*) FROM attendance_events WHERE worker_id = :w AND direction = 'checkOut'
                      AND at > :inAt AND at < :to""")
                    .param("w", workerId).param("inAt", Db.ts(inAt)).param("to", Db.ts(to))
                    .query(Integer.class).single() > 0;
            boolean laterIn = jdbc.sql("""
                    SELECT COUNT(*) FROM attendance_events WHERE worker_id = :w AND direction = 'checkIn'
                      AND at > :inAt AND at < :to""")
                    .param("w", workerId).param("inAt", Db.ts(inAt)).param("to", Db.ts(to))
                    .query(Integer.class).single() > 0;
            if (hasOut || laterIn || from.isAfter(inAt)) {
                continue;
            }
            add(new ExceptionRecord(Uuid7.next(), ExceptionKind.MISSING_OUT, clock.now(), workerId, false, eventId,
                    null, null, inAt, null, null));
        }
    }

    private static ExceptionRecord map(java.sql.ResultSet rs) throws java.sql.SQLException {
        String reason = rs.getString("reason");
        return new ExceptionRecord(Db.uuid(rs, "id"), Wire.parse(ExceptionKind.class, rs.getString("kind")),
                Db.instant(rs, "at"), Db.uuid(rs, "worker_id"), rs.getBoolean("resolved"), Db.uuid(rs, "event_id"),
                rs.getString("actor"), reason == null ? null : Wire.parse(ManualReason.class, reason),
                Db.instant(rs, "in_at"), Db.integer(rs, "minutes"), Db.integer(rs, "event_count"));
    }
}
