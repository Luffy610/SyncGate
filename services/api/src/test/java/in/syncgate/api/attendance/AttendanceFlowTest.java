package in.syncgate.api.attendance;

import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.common.Uuid7;
import in.syncgate.api.support.ApiTest;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.simple.JdbcClient;

class AttendanceFlowTest extends ApiTest {

    @Autowired JdbcClient jdbc;
    @Autowired AttendanceService attendance;
    @Autowired in.syncgate.api.audit.AuditService auditService;

    String owner;
    String device;
    String workerId;

    @BeforeEach
    void seed() throws Exception {
        owner = createOwner("123456");
        device = deviceToken();
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner,
                "{\"name\":\"Day\",\"startMinute\":360,\"endMinute\":840,\"graceMinutes\":10,\"weeklyOff\":7}")
                .andExpect(status().isOk());
        workerId = read(postJson("/api/v1/workers", owner,
                "{\"code\":\"W-0101\",\"name\":\"Ramesh Kumar\",\"dateOfBirth\":\"1990-05-01\",\"department\":\"Weaving\","
                        + "\"designation\":\"Operator\",\"shiftId\":\"" + shiftId + "\",\"language\":\"hi\"}"), "$.id");
    }

    String face() {
        return "{\"workerId\":\"" + workerId + "\",\"score\":0.91,\"margin\":0.22,\"liveness\":0.97}";
    }

    @Test
    void faceMarkAlternatesInOutUsesServerTimeAndEnforcesCooldown() throws Exception {
        // 05:52 is before the 06:00 start: on time. The client sends no time at all.
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isCreated())
                .andExpect(jsonPath("$.direction").value("checkIn")).andExpect(jsonPath("$.method").value("face"))
                .andExpect(jsonPath("$.onTime").value(true)).andExpect(jsonPath("$.at").value("2026-10-24T00:22:00Z"));

        // Within the 120 s cooldown a second mark is refused and says when the first one was.
        clock.advance(Duration.ofSeconds(60));
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("ALREADY_MARKED"))
                .andExpect(jsonPath("$.details.direction").value("checkIn"));

        clock.advance(Duration.ofHours(8));
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isCreated())
                .andExpect(jsonPath("$.direction").value("checkOut"));
        getJson("/api/v1/attendance/day?date=2026-10-24", device).andExpect(jsonPath("$", hasSize(2)));
        getJson("/api/v1/attendance/last?workerId=" + workerId, device).andExpect(jsonPath("$.direction").value("checkOut"));
    }

    @Test
    void lateInIsFlaggedAndNewDayStartsWithIn() throws Exception {
        clock.set("2026-10-24T06:25:00+05:30");
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(jsonPath("$.onTime").value(false));
        clock.set("2026-10-25T05:55:00+05:30");
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(jsonPath("$.direction").value("checkIn"));
    }

    @Test
    void clientRetryWithTheSameIdDoesNotDuplicate() throws Exception {
        String id = Uuid7.next().toString();
        String body = "{\"id\":\"" + id + "\",\"workerId\":\"" + workerId + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}";
        postJson("/api/v1/attendance/face-marks", device, body).andExpect(status().isCreated());
        clock.advance(Duration.ofSeconds(1));
        postJson("/api/v1/attendance/face-marks", device, body).andExpect(status().isCreated());
        getJson("/api/v1/attendance/day?date=2026-10-24", device).andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void thinMarginIsRecordedButFlaggedAndBadScoresAreRefused() throws Exception {
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + workerId + "\",\"score\":0.8,\"margin\":0.03,\"liveness\":0.9}")
                .andExpect(status().isCreated());
        getJson("/api/v1/exceptions", owner).andExpect(jsonPath("$[0].kind").value("lowMargin"));
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + workerId + "\",\"score\":1.5,\"margin\":0.2,\"liveness\":0.9}")
                .andExpect(status().isBadRequest());
    }

    @Test
    void manualEntryNeedsAReasonIsCappedAndCreatesAnException() throws Exception {
        String manual = "{\"workerId\":\"" + workerId + "\",\"reason\":\"notRecognised\",\"markedBy\":\"G-02\"}";
        postJson("/api/v1/attendance/manual-marks", device, "{\"workerId\":\"" + workerId + "\"}")
                .andExpect(status().isBadRequest());
        postJson("/api/v1/attendance/manual-marks", device,
                "{\"workerId\":\"" + workerId + "\",\"reason\":\"because\"}").andExpect(status().isBadRequest());
        for (int i = 0; i < 3; i++) {
            postJson("/api/v1/attendance/manual-marks", device, manual).andExpect(status().isCreated())
                    .andExpect(jsonPath("$.method").value("manual")).andExpect(jsonPath("$.markedBy").value("G-02"));
            clock.advance(Duration.ofMinutes(5));
        }
        postJson("/api/v1/attendance/manual-marks", device, manual).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("MANUAL_LIMIT_REACHED"));
        getJson("/api/v1/exceptions", owner).andExpect(jsonPath("$", hasSize(3)))
                .andExpect(jsonPath("$[0].kind").value("manual")).andExpect(jsonPath("$[0].actor").value("G-02"));
    }

    @Test
    void correctionResolvesTheMissingOutAndIsAuditedAndGuarded() throws Exception {
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isCreated());
        // Next morning the IN has no OUT: the server raises a missing-OUT exception.
        clock.set("2026-10-25T07:00:00+05:30");
        String list = getJson("/api/v1/exceptions", owner).andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].kind").value("missingOut")).andReturn().getResponse().getContentAsString();
        String exceptionId = com.jayway.jsonpath.JsonPath.read(list, "$[0].id");
        getJson("/api/v1/exceptions", owner).andExpect(jsonPath("$", hasSize(1))); // not duplicated

        String correction = "{\"workerId\":\"" + workerId + "\",\"at\":\"2026-10-24T08:30:00Z\",\"direction\":\"checkOut\","
                + "\"reason\":\"Forgot to scan\",\"exceptionId\":\"" + exceptionId + "\"}";
        postJson("/api/v1/attendance/corrections", device, correction).andExpect(status().isForbidden());
        // OUT before the IN is refused.
        postJson("/api/v1/attendance/corrections", owner, correction.replace("08:30:00Z", "00:10:00Z"))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("INVALID_CORRECTION"));
        // In the future is refused too.
        postJson("/api/v1/attendance/corrections", owner, correction.replace("2026-10-24T08:30", "2026-11-24T08:30"))
                .andExpect(status().isUnprocessableEntity());
        postJson("/api/v1/attendance/corrections", owner, correction.replace("Forgot to scan", "x"))
                .andExpect(status().isBadRequest());
        postJson("/api/v1/attendance/corrections", owner, correction).andExpect(status().isCreated())
                .andExpect(jsonPath("$.method").value("correction")).andExpect(jsonPath("$.direction").value("checkOut"));

        getJson("/api/v1/exceptions", owner).andExpect(jsonPath("$[0].resolved").value(true));
        // The original IN is still there: history is never rewritten.
        getJson("/api/v1/attendance/events?from=2026-10-23T18:30:00Z&to=2026-10-24T18:30:00Z", owner)
                .andExpect(jsonPath("$", hasSize(2)));
        getJson("/api/v1/audit", owner).andExpect(jsonPath("$[0].action").value("attendance.corrected"))
                .andExpect(jsonPath("$[1].action").value("exception.reviewed"));
    }

    @Test
    void chainsVerifyAndDetectTampering() throws Exception {
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isCreated());
        clock.advance(Duration.ofHours(8));
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isCreated());
        assertTrue(attendance.verify().ok());
        assertTrue(auditService.verify().ok());
        getJson("/api/v1/attendance/verify", owner).andExpect(jsonPath("$.ok").value(true))
                .andExpect(jsonPath("$.checked").value(2));
        getJson("/api/v1/attendance/verify", device).andExpect(status().isForbidden());

        // Someone with database access edits one event: the chain notices.
        jdbc.sql("UPDATE attendance_events SET on_time = FALSE WHERE seq = 1").update();
        var broken = attendance.verify();
        assertFalse(broken.ok());
        assertTrue(broken.brokenAtSeq() == 1L);
        // Deleting a row is detected as well.
        jdbc.sql("UPDATE attendance_events SET on_time = TRUE WHERE seq = 1").update();
        assertTrue(attendance.verify().ok());
        jdbc.sql("DELETE FROM attendance_events WHERE seq = 2").update();
        assertFalse(attendance.verify().ok());

        // Same for the audit log.
        jdbc.sql("UPDATE audit_log SET actor = 'Mallory' WHERE seq = 1").update();
        assertFalse(auditService.verify().ok());
    }

    @Test
    void inactiveWorkerCannotMarkAndUnknownWorkerIs404() throws Exception {
        putJson("/api/v1/workers/" + workerId + "/active", owner, "{\"active\":false}").andExpect(status().isNoContent());
        postJson("/api/v1/attendance/face-marks", device, face()).andExpect(status().isNotFound());
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + Uuid7.next() + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}")
                .andExpect(status().isNotFound());
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"not-a-uuid\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}")
                .andExpect(status().isNotFound());
    }

    @Test
    void rangeQueriesAreBounded() throws Exception {
        getJson("/api/v1/attendance/events?from=2026-01-01T00:00:00Z&to=2026-12-31T00:00:00Z", owner)
                .andExpect(status().isBadRequest());
        getJson("/api/v1/attendance/events?from=junk&to=junk", owner).andExpect(status().isBadRequest());
        getJson("/api/v1/attendance/day?date=24-10-2026", owner).andExpect(status().isBadRequest());
    }
}
