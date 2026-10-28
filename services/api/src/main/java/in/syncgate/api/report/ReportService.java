package in.syncgate.api.report;

import in.syncgate.api.attendance.AttendanceService;
import in.syncgate.api.attendance.AttendanceService.Event;
import in.syncgate.api.attendance.ExceptionService;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.domain.Enums.Direction;
import in.syncgate.api.domain.Enums.FaceStatus;
import in.syncgate.api.domain.Enums.MarkMethod;
import in.syncgate.api.shift.ShiftService;
import in.syncgate.api.worker.WorkerService;
import in.syncgate.api.worker.WorkerService.Worker;
import java.time.DayOfWeek;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.stereotype.Service;

/**
 * Daily view and monthly muster roll, computed on demand from the append-only
 * events (ADR-0012, ADR-0015). Nothing is stored, so a correction or a rule
 * change is reflected the next time a report is read.
 *
 * <p>Day codes: P present, L late, HD half day (worked under 4 h 30 m), A
 * absent, WO weekly off, empty for days that have not happened yet. Night
 * shifts are attributed to the calendar day of the IN for now; the full shift
 * engine (attribution date) is a later step.
 */
@Service
public class ReportService {

    static final Duration HALF_DAY_BELOW = Duration.ofMinutes(270);

    public record Filter(YearMonth month, String department, UUID shiftId, String contractor) {}

    public record MusterRow(Worker worker, int present, int absent, int late, double overtimeHours,
            boolean hasOpenExceptions, List<String> days) {}

    public record DailyRow(Worker worker, Instant inAt, Instant outAt, String status, boolean flagged) {}

    private final WorkerService workers;
    private final AttendanceService attendance;
    private final ExceptionService exceptions;
    private final ShiftService shifts;
    private final AppClock clock;

    public ReportService(WorkerService workers, AttendanceService attendance, ExceptionService exceptions,
            ShiftService shifts, AppClock clock) {
        this.workers = workers;
        this.attendance = attendance;
        this.exceptions = exceptions;
        this.shifts = shifts;
        this.clock = clock;
    }

    public List<MusterRow> monthly(Filter filter) {
        YearMonth month = filter.month();
        Instant from = month.atDay(1).atStartOfDay(clock.zone()).toInstant();
        Instant to = month.plusMonths(1).atDay(1).atStartOfDay(clock.zone()).toInstant();
        List<Event> events = attendance.between(from, to);
        // No marks at all: the month predates SyncGate, so there is no muster.
        if (events.isEmpty()) {
            return List.of();
        }
        Set<UUID> open = exceptions.all().stream().filter(e -> !e.resolved() && e.workerId() != null)
                .map(ExceptionService.ExceptionRecord::workerId).collect(Collectors.toSet());
        Map<UUID, List<Event>> byWorker = events.stream().collect(Collectors.groupingBy(Event::workerId));
        Map<UUID, ShiftService.Shift> shiftById = shifts.all().stream()
                .collect(Collectors.toMap(ShiftService.Shift::id, s -> s));
        int lastCounted = lastCountedDay(month);
        List<MusterRow> rows = new ArrayList<>();

        for (Worker worker : filtered(filter)) {
            ShiftService.Shift shift = shiftById.get(worker.shiftId());
            DayOfWeek weeklyOff = DayOfWeek.of(shift == null ? 7 : shift.weeklyOff());
            double shiftHours = shift == null ? 8 : shiftHours(shift);
            Map<LocalDate, List<Event>> perDay = byWorker.getOrDefault(worker.id(), List.of()).stream()
                    .collect(Collectors.groupingBy(e -> e.at().atZone(clock.zone()).toLocalDate()));
            int present = 0;
            int absent = 0;
            int late = 0;
            double overtime = 0;
            List<String> days = new ArrayList<>();
            for (int d = 1; d <= month.lengthOfMonth(); d++) {
                LocalDate day = month.atDay(d);
                if (d > lastCounted || day.isBefore(worker.joinedOn())) {
                    days.add("");
                    continue;
                }
                if (day.getDayOfWeek() == weeklyOff) {
                    days.add("WO");
                    continue;
                }
                List<Event> dayEvents = perDay.getOrDefault(day, List.of()).stream()
                        .sorted(Comparator.comparing(Event::at)).toList();
                Event firstIn = dayEvents.stream().filter(e -> e.direction() == Direction.CHECK_IN).findFirst()
                        .orElse(null);
                if (firstIn == null) {
                    if (day.equals(clock.today())) {
                        days.add(""); // today is not over: not absent yet
                    } else {
                        absent++;
                        days.add("A");
                    }
                    continue;
                }
                present++;
                Event lastOut = dayEvents.stream()
                        .filter(e -> e.direction() == Direction.CHECK_OUT && e.at().isAfter(firstIn.at()))
                        .reduce((a, b) -> b).orElse(null);
                Duration worked = lastOut == null ? null : Duration.between(firstIn.at(), lastOut.at());
                if (worked != null && worked.compareTo(HALF_DAY_BELOW) < 0) {
                    days.add("HD");
                } else if (!firstIn.onTime()) {
                    late++;
                    days.add("L");
                } else {
                    days.add("P");
                }
                if (worked != null) {
                    overtime += overtime(worked, shiftHours);
                }
            }
            rows.add(new MusterRow(worker, present, absent, late, overtime, open.contains(worker.id()), days));
        }
        return rows;
    }

    public List<DailyRow> daily(LocalDate day) {
        List<Event> events = attendance.forDay(day);
        Set<UUID> open = exceptions.all().stream().filter(e -> !e.resolved() && e.workerId() != null)
                .map(ExceptionService.ExceptionRecord::workerId).collect(Collectors.toSet());
        Map<UUID, List<Event>> byWorker = events.stream().collect(Collectors.groupingBy(Event::workerId));
        List<DailyRow> rows = new ArrayList<>();
        for (Worker worker : filtered(new Filter(YearMonth.from(day), null, null, null))) {
            List<Event> mine = byWorker.getOrDefault(worker.id(), List.of());
            Event firstIn = mine.stream().filter(e -> e.direction() == Direction.CHECK_IN)
                    .min(Comparator.comparing(Event::at)).orElse(null);
            Event lastOut = firstIn == null ? null : mine.stream()
                    .filter(e -> e.direction() == Direction.CHECK_OUT && e.at().isAfter(firstIn.at()))
                    .max(Comparator.comparing(Event::at)).orElse(null);
            String status;
            if (firstIn == null) {
                status = "A";
            } else if (lastOut != null && Duration.between(firstIn.at(), lastOut.at()).compareTo(HALF_DAY_BELOW) < 0) {
                status = "HD";
            } else {
                status = firstIn.onTime() ? "P" : "L";
            }
            boolean flagged = open.contains(worker.id())
                    || mine.stream().anyMatch(e -> e.method() != MarkMethod.FACE);
            rows.add(new DailyRow(worker, firstIn == null ? null : firstIn.at(),
                    lastOut == null ? null : lastOut.at(), status, flagged));
        }
        return rows;
    }

    /** Non-weekly-off days that have happened so far (Sunday off). */
    public int workingDays(YearMonth month) {
        int count = 0;
        for (int d = 1; d <= lastCountedDay(month); d++) {
            if (month.atDay(d).getDayOfWeek() != DayOfWeek.SUNDAY) {
                count++;
            }
        }
        return count;
    }

    private List<Worker> filtered(Filter f) {
        return workers.all().stream()
                .filter(w -> w.active() && w.faceStatus() == FaceStatus.ENROLLED)
                .filter(w -> f.department() == null || w.department().equals(f.department()))
                .filter(w -> f.shiftId() == null || w.shiftId().equals(f.shiftId()))
                .filter(w -> f.contractor() == null || f.contractor().equals(w.contractor()))
                .sorted(Comparator.comparing(Worker::name)).toList();
    }

    private int lastCountedDay(YearMonth month) {
        LocalDate today = clock.today();
        YearMonth current = YearMonth.from(today);
        if (month.equals(current)) {
            return today.getDayOfMonth();
        }
        return month.isAfter(current) ? 0 : month.lengthOfMonth();
    }

    static double shiftHours(ShiftService.Shift shift) {
        int minutes = shift.endMinute() - shift.startMinute();
        if (minutes <= 0) {
            minutes += 24 * 60;
        }
        return minutes / 60.0;
    }

    /** Hours beyond the shift length, rounded down to 30 minutes; under 30 minutes is not overtime. */
    static double overtime(Duration worked, double shiftHours) {
        double extra = worked.toMinutes() / 60.0 - shiftHours;
        return extra < 0.5 ? 0 : Math.floor(extra * 2) / 2;
    }

}
