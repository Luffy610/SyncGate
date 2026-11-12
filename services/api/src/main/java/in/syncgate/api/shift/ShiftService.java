package in.syncgate.api.shift;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** Shift windows (ADR-0012). Times are minutes since midnight. */
@Service
public class ShiftService {

    /** A shift window; {@code endMinute <= startMinute} means it crosses midnight. */
    public record Shift(UUID id, String name, int startMinute, int endMinute, int graceMinutes, int weeklyOff) {

        public boolean crossesMidnight() {
            return endMinute <= startMinute;
        }

        /** True when an IN at {@code minuteOfDay} is within the grace period. */
        public boolean isOnTime(int minuteOfDay) {
            if (crossesMidnight() && minuteOfDay < endMinute) {
                return true;
            }
            return minuteOfDay <= startMinute + graceMinutes;
        }
    }

    private final JdbcClient jdbc;
    private final AppClock clock;
    private final AuditService audit;

    public ShiftService(JdbcClient jdbc, AppClock clock, AuditService audit) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.audit = audit;
    }

    public List<Shift> all() {
        return jdbc.sql("SELECT id, name, start_minute, end_minute, grace_minutes, weekly_off FROM shifts ORDER BY start_minute, name")
                .query((rs, i) -> new Shift(Db.uuid(rs, "id"), rs.getString("name"), rs.getInt("start_minute"),
                        rs.getInt("end_minute"), rs.getInt("grace_minutes"), rs.getInt("weekly_off")))
                .list();
    }

    public Optional<Shift> find(UUID id) {
        return all().stream().filter(s -> s.id().equals(id)).findFirst();
    }

    /** Create or update with a client-chosen id, so retries are idempotent. */
    @Transactional
    public Shift upsert(Shift shift, String actor) {
        if (shift.startMinute() == shift.endMinute()) {
            throw ApiException.invalid("A shift cannot start and end at the same time");
        }
        boolean exists = find(shift.id()).isPresent();
        if (exists) {
            jdbc.sql("""
                    UPDATE shifts SET name = :n, start_minute = :s, end_minute = :e, grace_minutes = :g,
                        weekly_off = :w, updated_at = :now WHERE id = :id""")
                    .param("n", shift.name()).param("s", shift.startMinute()).param("e", shift.endMinute())
                    .param("g", shift.graceMinutes()).param("w", shift.weeklyOff())
                    .param("now", Db.ts(clock.now())).param("id", shift.id()).update();
        } else {
            jdbc.sql("""
                    INSERT INTO shifts (id, name, start_minute, end_minute, grace_minutes, weekly_off, updated_at)
                    VALUES (:id, :n, :s, :e, :g, :w, :now)""")
                    .param("id", shift.id()).param("n", shift.name()).param("s", shift.startMinute())
                    .param("e", shift.endMinute()).param("g", shift.graceMinutes()).param("w", shift.weeklyOff())
                    .param("now", Db.ts(clock.now())).update();
        }
        audit.record(actor, exists ? "shift.updated" : "shift.created", shift.name());
        return shift;
    }
}
