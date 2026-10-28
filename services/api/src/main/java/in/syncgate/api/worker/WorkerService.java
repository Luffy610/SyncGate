package in.syncgate.api.worker;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import in.syncgate.api.domain.Enums.FaceStatus;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.shift.ShiftService;
import java.time.LocalDate;
import java.time.Period;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Workers and their consents. Erasure follows ADR-0008: personal data is
 * removed, but a worker with attendance history stays as a wage-record stub
 * (code, name, attendance) until the legal retention period ends.
 */
@Service
public class WorkerService {

    public static final int MINIMUM_AGE = 18;
    private static final Pattern CODE = Pattern.compile("^[A-Za-z0-9-]{1,20}$");
    private static final String COLUMNS = "id, code, name, date_of_birth, department, designation, shift_id, "
            + "contractor, phone, language, face_status, active, on_leave, created_at";

    public record Worker(UUID id, String code, String name, LocalDate dateOfBirth, String department,
            String designation, UUID shiftId, String contractor, String phone, String language,
            FaceStatus faceStatus, boolean active, boolean onLeave, LocalDate joinedOn) {}

    public record NewWorker(UUID id, String code, String name, LocalDate dateOfBirth, String department,
            String designation, UUID shiftId, String contractor, String phone, String language) {}

    private final JdbcClient jdbc;
    private final AppClock clock;
    private final AuditService audit;
    private final ShiftService shifts;

    public WorkerService(JdbcClient jdbc, AppClock clock, AuditService audit, ShiftService shifts) {
        this.jdbc = jdbc;
        this.clock = clock;
        this.audit = audit;
        this.shifts = shifts;
    }

    public List<Worker> all() {
        return jdbc.sql("SELECT " + COLUMNS + " FROM workers WHERE erased = FALSE ORDER BY name, code")
                .query((rs, i) -> map(rs)).list();
    }

    public Optional<Worker> find(UUID id) {
        return jdbc.sql("SELECT " + COLUMNS + " FROM workers WHERE id = :id AND erased = FALSE")
                .param("id", id).query((rs, i) -> map(rs)).optional();
    }

    public Worker require(UUID id) {
        return find(id).orElseThrow(() -> ApiException.notFound("Worker"));
    }

    public String nextCode() {
        int max = jdbc.sql("SELECT code FROM workers").query(String.class).list().stream()
                .filter(c -> c.matches("^W-\\d+$"))
                .mapToInt(c -> Integer.parseInt(c.substring(2)))
                .max().orElse(100);
        return String.format("W-%04d", max + 1);
    }

    public boolean isCodeUnique(String code, UUID except) {
        Integer count = jdbc.sql("SELECT COUNT(*) FROM workers WHERE LOWER(code) = LOWER(:c) AND id <> :ex")
                .param("c", code)
                .param("ex", except == null ? new UUID(0, 0) : except)
                .query(Integer.class).single();
        return count == 0;
    }

    @Transactional
    public Worker add(NewWorker in, String actor) {
        validate(in.code(), in.name(), in.dateOfBirth(), in.language());
        shifts.find(in.shiftId()).orElseThrow(() -> ApiException.invalid("Unknown shift"));
        if (!isCodeUnique(in.code(), null)) {
            throw ApiException.conflict("DUPLICATE_WORKER_CODE", "That worker ID is already in use");
        }
        UUID id = in.id() == null ? Uuid7.next() : in.id();
        if (jdbc.sql("SELECT COUNT(*) FROM workers WHERE id = :id").param("id", id).query(Integer.class).single() > 0) {
            // Idempotent retry of the same enrolment.
            return require(id);
        }
        ensureDepartment(in.department());
        jdbc.sql("""
                INSERT INTO workers (id, code, name, date_of_birth, department, designation, shift_id, contractor,
                    phone, language, face_status, active, on_leave, erased, created_at)
                VALUES (:id, :code, :name, :dob, :dep, :des, :shift, :con, :phone, :lang, 'needsFace', TRUE, FALSE,
                    FALSE, :now)""")
                .param("id", id).param("code", in.code().strip()).param("name", clean(in.name()))
                .param("dob", in.dateOfBirth()).param("dep", clean(in.department()))
                .param("des", clean(in.designation())).param("shift", in.shiftId())
                .param("con", blankToNull(in.contractor())).param("phone", blankToNull(in.phone()))
                .param("lang", in.language()).param("now", Db.ts(clock.now()))
                .update();
        audit.record(actor, "worker.enrolled", in.code() + " " + clean(in.name()));
        return require(id);
    }

    @Transactional
    public Worker update(UUID id, NewWorker in, String actor) {
        Worker existing = require(id);
        validate(in.code(), in.name(), in.dateOfBirth(), in.language());
        shifts.find(in.shiftId()).orElseThrow(() -> ApiException.invalid("Unknown shift"));
        if (!isCodeUnique(in.code(), id)) {
            throw ApiException.conflict("DUPLICATE_WORKER_CODE", "That worker ID is already in use");
        }
        ensureDepartment(in.department());
        jdbc.sql("""
                UPDATE workers SET code = :code, name = :name, date_of_birth = :dob, department = :dep,
                    designation = :des, shift_id = :shift, contractor = :con, phone = :phone, language = :lang
                WHERE id = :id""")
                .param("code", in.code().strip()).param("name", clean(in.name())).param("dob", in.dateOfBirth())
                .param("dep", clean(in.department())).param("des", clean(in.designation()))
                .param("shift", in.shiftId()).param("con", blankToNull(in.contractor()))
                .param("phone", blankToNull(in.phone())).param("lang", in.language()).param("id", id)
                .update();
        audit.record(actor, "worker.updated", existing.code());
        return require(id);
    }

    @Transactional
    public void setFaceStatus(UUID id, FaceStatus status, String actor) {
        Worker worker = require(id);
        jdbc.sql("UPDATE workers SET face_status = :s WHERE id = :id")
                .param("s", Wire.of(status)).param("id", id).update();
        audit.record(actor, status == FaceStatus.ENROLLED ? "worker.face_enrolled" : "worker.face_cleared",
                worker.code());
    }

    @Transactional
    public void setActive(UUID id, boolean active, String actor) {
        Worker worker = require(id);
        jdbc.sql("UPDATE workers SET active = :a WHERE id = :id").param("a", active).param("id", id).update();
        audit.record(actor, active ? "worker.activated" : "worker.deactivated", worker.code());
    }

    /** Erase personal data; keep a wage-record stub when there is attendance history. */
    @Transactional
    public void delete(UUID id, String actor) {
        Worker worker = require(id);
        int events = jdbc.sql("SELECT COUNT(*) FROM attendance_events WHERE worker_id = :id")
                .param("id", id).query(Integer.class).single();
        jdbc.sql("DELETE FROM tally_mappings WHERE worker_id = :id").param("id", id).update();
        if (events == 0) {
            jdbc.sql("DELETE FROM exceptions WHERE worker_id = :id").param("id", id).update();
            jdbc.sql("DELETE FROM consents WHERE worker_id = :id").param("id", id).update();
            jdbc.sql("DELETE FROM workers WHERE id = :id").param("id", id).update();
        } else {
            jdbc.sql("""
                    UPDATE workers SET erased = TRUE, active = FALSE, face_status = 'needsFace',
                        date_of_birth = :dob, phone = NULL, contractor = NULL, designation = '[erased]'
                    WHERE id = :id""")
                    .param("dob", LocalDate.of(1900, 1, 1)).param("id", id).update();
        }
        audit.record(actor, "worker.erased", worker.code() + (events == 0 ? " (removed)" : " (wage stub kept)"));
    }

    public List<String> departments() {
        return jdbc.sql("SELECT name FROM departments ORDER BY name").query(String.class).list();
    }

    @Transactional
    public void addDepartment(String name, String actor) {
        String clean = clean(name);
        if (clean.isEmpty() || clean.length() > 80) {
            throw ApiException.invalid("Department name must be 1 to 80 characters");
        }
        ensureDepartment(clean);
        audit.record(actor, "department.added", clean);
    }

    public List<String> contractors() {
        return jdbc.sql("SELECT DISTINCT contractor FROM workers WHERE contractor IS NOT NULL AND erased = FALSE "
                        + "ORDER BY contractor")
                .query(String.class).list();
    }

    // ---- consents (append-only) -------------------------------------------

    @Transactional
    public void recordConsent(UUID workerId, String noticeVersion, String language, String adminId, String actor) {
        Worker worker = require(workerId);
        jdbc.sql("""
                INSERT INTO consents (id, worker_id, notice_version, language, admin_id, accepted_at)
                VALUES (:id, :w, :v, :l, :a, :at)""")
                .param("id", Uuid7.next()).param("w", workerId).param("v", noticeVersion).param("l", language)
                .param("a", adminId).param("at", Db.ts(clock.now())).update();
        audit.record(actor, "consent.recorded", worker.code() + " " + noticeVersion + " " + language);
    }

    public boolean hasConsent(UUID workerId) {
        return jdbc.sql("SELECT COUNT(*) FROM consents WHERE worker_id = :w").param("w", workerId)
                .query(Integer.class).single() > 0;
    }

    // ---- helpers -----------------------------------------------------------

    private void validate(String code, String name, LocalDate dob, String language) {
        if (code == null || !CODE.matcher(code.strip()).matches()) {
            throw ApiException.invalid("Worker ID may use letters, digits and dashes (1 to 20 characters)");
        }
        if (name == null || clean(name).isEmpty() || clean(name).length() > 120) {
            throw ApiException.invalid("Name must be 1 to 120 characters");
        }
        if (dob == null || dob.isAfter(clock.today())) {
            throw ApiException.invalid("Date of birth is not valid");
        }
        if (Period.between(dob, clock.today()).getYears() < MINIMUM_AGE) {
            throw new ApiException(HttpStatus.UNPROCESSABLE_ENTITY, "WORKER_UNDER_AGE",
                    "Workers must be at least 18 years old");
        }
        if (language == null || !language.matches("^(en|hi|gu|ta|pa|mr)$")) {
            throw ApiException.invalid("Unknown language");
        }
    }

    private void ensureDepartment(String name) {
        String clean = clean(name);
        jdbc.sql("INSERT INTO departments (name) SELECT :n WHERE NOT EXISTS (SELECT 1 FROM departments WHERE name = :n)")
                .param("n", clean).update();
    }

    static String clean(String text) {
        return text == null ? "" : text.replaceAll("\\p{Cntrl}", " ").strip().replaceAll("\\s{2,}", " ");
    }

    private static String blankToNull(String text) {
        String clean = clean(text);
        return clean.isEmpty() ? null : clean;
    }

    private static Worker map(java.sql.ResultSet rs) throws java.sql.SQLException {
        return new Worker(Db.uuid(rs, "id"), rs.getString("code"), rs.getString("name"),
                rs.getObject("date_of_birth", LocalDate.class), rs.getString("department"),
                rs.getString("designation"), Db.uuid(rs, "shift_id"), rs.getString("contractor"),
                rs.getString("phone"), rs.getString("language"),
                Wire.parse(FaceStatus.class, rs.getString("face_status")), rs.getBoolean("active"),
                rs.getBoolean("on_leave"), Db.instant(rs, "created_at").atZone(java.time.ZoneId.of("Asia/Kolkata")).toLocalDate());
    }
}
