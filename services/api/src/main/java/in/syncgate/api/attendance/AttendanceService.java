package in.syncgate.api.attendance;

import in.syncgate.api.attendance.ExceptionService.ExceptionRecord;
import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.ChainService;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import in.syncgate.api.domain.Enums.Direction;
import in.syncgate.api.domain.Enums.ExceptionKind;
import in.syncgate.api.domain.Enums.ManualReason;
import in.syncgate.api.domain.Enums.MarkMethod;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.recognition.FaceRecognitionPort;
import in.syncgate.api.shift.ShiftService;
import in.syncgate.api.worker.WorkerService;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZonedDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Attendance facts (ADR-0011). Events are append-only and hash-chained. The
 * server stamps time itself, decides direction and applies the cooldown and
 * manual-entry limits, so the phone cannot forge or reorder marks. All writes
 * first lock the chain head, which also makes the cooldown check race-free.
 */
@Service
public class AttendanceService {

    public static final String CHAIN = "attendance";
    public static final int MANUAL_LIMIT_PER_DAY = 3;
    private static final Duration MAX_CORRECTION_AGE = Duration.ofDays(62);
    private static final Duration FUTURE_TOLERANCE = Duration.ofMinutes(5);
    private static final String COLUMNS = "seq, id, worker_id, at, direction, method, reason, marked_by, on_time, "
            + "match_score, match_margin, liveness, prev_hash, hash";

    public record Event(UUID id, UUID workerId, Instant at, Direction direction, MarkMethod method, String reason,
            String markedBy, boolean onTime) {}

    private record Row(long seq, Event event, Double score, Double margin, Double liveness, String prevHash,
            String hash) {}

    public record Verification(boolean ok, long checked, Long brokenAtSeq) {}

    private final JdbcClient jdbc;
    private final ChainService chain;
    private final AppClock clock;
    private final AuditService audit;
    private final WorkerService workers;
    private final ShiftService shifts;
    private final ExceptionService exceptions;
    private final FaceRecognitionPort recognition;
    private final in.syncgate.api.settings.SettingsService settings;

    public AttendanceService(JdbcClient jdbc, ChainService chain, AppClock clock, AuditService audit,
            WorkerService workers, ShiftService shifts, ExceptionService exceptions, FaceRecognitionPort recognition,
            in.syncgate.api.settings.SettingsService settings) {
        this.jdbc = jdbc;
        this.chain = chain;
        this.clock = clock;
        this.audit = audit;
        this.workers = workers;
        this.shifts = shifts;
        this.exceptions = exceptions;
        this.recognition = recognition;
        this.settings = settings;
    }

    // ---- writes ------------------------------------------------------------

    /** A face match reported by the on-device pipeline. */
    @Transactional
    public Event markFace(UUID eventId, UUID workerId, double score, double margin, double liveness) {
        ChainService.Link link = chain.reserve(CHAIN);
        Optional<Event> existing = existing(eventId);
        if (existing.isPresent()) {
            return existing.get();
        }
        WorkerService.Worker worker = workers.find(workerId).filter(WorkerService.Worker::active)
                .orElseThrow(() -> ApiException.notFound("Worker"));
        var verdict = recognition.verify(new FaceRecognitionPort.MatchClaim(workerId, score, margin, liveness));
        if (!verdict.accepted()) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "NOT_RECOGNISED", "Match was not accepted");
        }
        Instant now = clock.now();
        Optional<Event> last = lastEvent(workerId);
        int cooldown = settings.cooldownSeconds();
        if (last.isPresent() && inCooldown(last.get().at(), now, cooldown)) {
            throw new ApiException(HttpStatus.CONFLICT, "ALREADY_MARKED", "Already marked a moment ago",
                    Map.of("at", last.get().at().toString(), "direction", Wire.of(last.get().direction())));
        }
        Direction direction = nextDirection(last.orElse(null), now);
        Event event = insert(link, eventId, worker, now, direction, MarkMethod.FACE, null, null, score, margin, liveness);
        if (verdict.lowMargin()) {
            exceptions.add(new ExceptionRecord(Uuid7.next(), ExceptionKind.LOW_MARGIN, now, workerId, false,
                    event.id(), null, null, null, null, null));
        }
        return event;
    }

    /** Guard fallback (ADR-0004 section 3): required reason, flagged, capped per day. */
    @Transactional
    public Event markManual(UUID eventId, UUID workerId, ManualReason reason, String actor) {
        ChainService.Link link = chain.reserve(CHAIN);
        Optional<Event> existing = existing(eventId);
        if (existing.isPresent()) {
            return existing.get();
        }
        WorkerService.Worker worker = workers.find(workerId).orElseThrow(() -> ApiException.notFound("Worker"));
        Instant now = clock.now();
        Instant dayStart = clock.today().atStartOfDay(clock.zone()).toInstant();
        int manualToday = jdbc.sql("""
                SELECT COUNT(*) FROM attendance_events
                WHERE worker_id = :w AND method = 'manual' AND at >= :from AND at < :to""")
                .param("w", workerId).param("from", Db.ts(dayStart))
                .param("to", Db.ts(dayStart.plus(Duration.ofDays(1)))).query(Integer.class).single();
        if (manualToday >= MANUAL_LIMIT_PER_DAY) {
            throw ApiException.conflict("MANUAL_LIMIT_REACHED", "Manual entry limit reached for today");
        }
        Direction direction = nextDirection(lastEvent(workerId).orElse(null), now);
        Event event = insert(link, eventId, worker, now, direction, MarkMethod.MANUAL, Wire.of(reason), actor,
                null, null, null);
        exceptions.add(new ExceptionRecord(Uuid7.next(), ExceptionKind.MANUAL, now, workerId, false, event.id(),
                actor, reason, null, null, null));
        audit.record(actor, "attendance.manual", worker.code() + " " + Wire.of(direction) + " " + Wire.of(reason));
        return event;
    }

    /** A correction is a new event that supersedes nothing: history stays visible. */
    @Transactional
    public Event correct(UUID eventId, UUID workerId, Instant at, Direction direction, String reason, String actor,
            UUID exceptionId) {
        ChainService.Link link = chain.reserve(CHAIN);
        Optional<Event> existing = existing(eventId);
        if (existing.isPresent()) {
            return existing.get();
        }
        WorkerService.Worker worker = workers.find(workerId).orElseThrow(() -> ApiException.notFound("Worker"));
        Instant now = clock.now();
        String why = reason == null ? "" : reason.replaceAll("\\p{Cntrl}", " ").strip();
        if (why.length() < 3 || why.length() > 200) {
            throw ApiException.invalid("A reason of 3 to 200 characters is required");
        }
        if (at.isAfter(now.plus(FUTURE_TOLERANCE)) || at.isBefore(now.minus(MAX_CORRECTION_AGE))) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "INVALID_CORRECTION",
                    "That time cannot be recorded");
        }
        if (direction == Direction.CHECK_OUT) {
            // An OUT must come after the worker's IN on that day.
            Optional<Instant> firstIn = firstInOnDay(workerId, at);
            if (firstIn.isPresent() && !at.isAfter(firstIn.get())) {
                throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "INVALID_CORRECTION",
                        "OUT must be after IN");
            }
        }
        Event event = insert(link, eventId, worker, at, direction, MarkMethod.CORRECTION, why, actor, null, null, null);
        if (exceptionId != null) {
            exceptions.resolve(exceptionId, actor);
        }
        audit.record(actor, "attendance.corrected",
                worker.code() + " " + Wire.of(direction) + " " + at + " (" + why + ")");
        return event;
    }

    private Event insert(ChainService.Link link, UUID eventId, WorkerService.Worker worker, Instant at,
            Direction direction, MarkMethod method, String reason, String markedBy, Double score, Double margin,
            Double liveness) {
        UUID id = eventId == null ? Uuid7.next() : eventId;
        Instant when = AppClock.millis(at);
        boolean onTime = onTime(worker, direction, when);
        String hash = hash(link.prevHash(), id, worker.id(), when, direction, method, reason, markedBy, onTime, score,
                margin, liveness);
        jdbc.sql("""
                INSERT INTO attendance_events (seq, id, worker_id, at, direction, method, reason, marked_by, on_time,
                    match_score, match_margin, liveness, prev_hash, hash)
                VALUES (:seq, :id, :w, :at, :dir, :method, :reason, :by, :ontime, :score, :margin, :live, :prev, :hash)""")
                .param("seq", link.seq()).param("id", id).param("w", worker.id()).param("at", Db.ts(when))
                .param("dir", Wire.of(direction)).param("method", Wire.of(method)).param("reason", reason)
                .param("by", markedBy).param("ontime", onTime).param("score", score).param("margin", margin)
                .param("live", liveness).param("prev", link.prevHash()).param("hash", hash).update();
        chain.commit(CHAIN, link.seq(), hash);
        return new Event(id, worker.id(), when, direction, method, reason, markedBy, onTime);
    }

    // ---- reads -------------------------------------------------------------

    public List<Event> forDay(LocalDate day) {
        Instant from = day.atStartOfDay(clock.zone()).toInstant();
        return between(from, from.plus(Duration.ofDays(1)));
    }

    public List<Event> between(Instant from, Instant to) {
        if (!to.isAfter(from) || Duration.between(from, to).compareTo(Duration.ofDays(93)) > 0) {
            throw ApiException.invalid("Choose a range of at most 93 days");
        }
        return jdbc.sql("SELECT " + COLUMNS + " FROM attendance_events WHERE at >= :from AND at < :to ORDER BY at, seq")
                .param("from", Db.ts(from)).param("to", Db.ts(to))
                .query((rs, i) -> map(rs).event()).list();
    }

    public Optional<Event> lastEvent(UUID workerId) {
        return jdbc.sql("SELECT " + COLUMNS + " FROM attendance_events WHERE worker_id = :w ORDER BY at DESC, seq DESC LIMIT 1")
                .param("w", workerId).query((rs, i) -> map(rs).event()).optional();
    }

    /** Re-computes the whole chain from genesis. */
    public Verification verify() {
        String prev = chain.genesis(CHAIN);
        if (prev == null) {
            return new Verification(true, 0, null);
        }
        var rows = jdbc.sql("SELECT " + COLUMNS + " FROM attendance_events ORDER BY seq")
                .query((rs, i) -> map(rs)).list();
        long expected = 1;
        long checked = 0;
        for (Row row : rows) {
            Event e = row.event();
            String hash = hash(prev, e.id(), e.workerId(), e.at(), e.direction(), e.method(), e.reason(),
                    e.markedBy(), e.onTime(), row.score(), row.margin(), row.liveness());
            if (row.seq() != expected || !prev.equals(row.prevHash()) || !hash.equals(row.hash())) {
                return new Verification(false, checked, row.seq());
            }
            prev = hash;
            expected++;
            checked++;
        }
        if (!prev.equals(chain.head(CHAIN)) || chain.headSeq(CHAIN) != checked) {
            return new Verification(false, checked, checked + 1);
        }
        return new Verification(true, checked, null);
    }

    // ---- rules (mirror AttendanceRules in the Flutter sg_domain package) ----

    boolean inCooldown(Instant last, Instant now, int cooldownSeconds) {
        Duration elapsed = Duration.between(last, now);
        return !elapsed.isNegative() && elapsed.compareTo(Duration.ofSeconds(cooldownSeconds)) < 0;
    }

    Direction nextDirection(Event last, Instant now) {
        if (last == null || !sameDay(last.at(), now)) {
            return Direction.CHECK_IN;
        }
        return last.direction() == Direction.CHECK_IN ? Direction.CHECK_OUT : Direction.CHECK_IN;
    }

    private boolean sameDay(Instant a, Instant b) {
        return a.atZone(clock.zone()).toLocalDate().equals(b.atZone(clock.zone()).toLocalDate());
    }

    private boolean onTime(WorkerService.Worker worker, Direction direction, Instant at) {
        if (direction != Direction.CHECK_IN) {
            return true;
        }
        return shifts.find(worker.shiftId()).map(shift -> {
            ZonedDateTime local = at.atZone(clock.zone());
            return shift.isOnTime(local.getHour() * 60 + local.getMinute());
        }).orElse(true);
    }

    private Optional<Instant> firstInOnDay(UUID workerId, Instant at) {
        LocalDate day = at.atZone(clock.zone()).toLocalDate();
        Instant from = day.atStartOfDay(clock.zone()).toInstant();
        return jdbc.sql("""
                SELECT MIN(at) FROM attendance_events
                WHERE worker_id = :w AND direction = 'checkIn' AND at >= :from AND at < :to""")
                .param("w", workerId).param("from", Db.ts(from)).param("to", Db.ts(from.plus(Duration.ofDays(1))))
                .query((rs, i) -> {
                    java.time.OffsetDateTime first = rs.getObject(1, java.time.OffsetDateTime.class);
                    return first == null ? Optional.<Instant>empty() : Optional.of(first.toInstant());
                }).single();
    }

    private Optional<Event> existing(UUID eventId) {
        if (eventId == null) {
            return Optional.empty();
        }
        return jdbc.sql("SELECT " + COLUMNS + " FROM attendance_events WHERE id = :id").param("id", eventId)
                .query((rs, i) -> map(rs).event()).optional();
    }

    static String hash(String prev, UUID id, UUID workerId, Instant at, Direction direction, MarkMethod method,
            String reason, String markedBy, boolean onTime, Double score, Double margin, Double liveness) {
        return ChainService.hash(prev, id.toString(), workerId.toString(), Long.toString(at.toEpochMilli()),
                Wire.of(direction), Wire.of(method), reason, markedBy, Boolean.toString(onTime),
                score == null ? null : Double.toString(score), margin == null ? null : Double.toString(margin),
                liveness == null ? null : Double.toString(liveness));
    }

    private static Row map(java.sql.ResultSet rs) throws java.sql.SQLException {
        Event event = new Event(Db.uuid(rs, "id"), Db.uuid(rs, "worker_id"), Db.instant(rs, "at"),
                Wire.parse(Direction.class, rs.getString("direction")),
                Wire.parse(MarkMethod.class, rs.getString("method")), rs.getString("reason"),
                rs.getString("marked_by"), rs.getBoolean("on_time"));
        return new Row(rs.getLong("seq"), event, Db.decimal(rs, "match_score"), Db.decimal(rs, "match_margin"),
                Db.decimal(rs, "liveness"), rs.getString("prev_hash"), rs.getString("hash"));
    }
}
