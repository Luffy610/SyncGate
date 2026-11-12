package in.syncgate.api.backup;

import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.common.Uuid7;
import in.syncgate.api.support.ApiTest;
import java.time.Duration;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.ResultActions;

class BackupFlowTest extends ApiTest {

    @Autowired JdbcClient jdbc;

    String owner;
    String device;
    String workerId;

    @BeforeEach
    void seed() throws Exception {
        owner = createOwner("123456");
        device = deviceToken();
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner,
                "{\"name\":\"Day\",\"startMinute\":360,\"endMinute\":840,\"graceMinutes\":10,\"weeklyOff\":7}");
        workerId = read(postJson("/api/v1/workers", owner,
                "{\"code\":\"W-0101\",\"name\":\"रमेश कुमार\",\"dateOfBirth\":\"1990-05-01\",\"department\":\"Weaving\","
                        + "\"designation\":\"Operator\",\"shiftId\":\"" + shiftId + "\",\"language\":\"hi\"}"), "$.id");
        putJson("/api/v1/workers/" + workerId + "/face-status", owner, "{\"status\":\"enrolled\"}");
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + workerId + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}");
        clock.advance(Duration.ofHours(8));
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + workerId + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}");
    }

    byte[] takeBackup() throws Exception {
        putJson("/api/v1/backups/passphrase", owner, "{\"passphrase\":\"correct horse battery\"}")
                .andExpect(status().isNoContent());
        String id = read(postJson("/api/v1/backups", owner, "{}").andExpect(status().isCreated()), "$.id");
        return mvc.perform(get("/api/v1/backups/" + id + "/download").header("Authorization", "Bearer " + owner))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsByteArray();
    }

    ResultActions restore(byte[] file, String passphrase, String token) throws Exception {
        var request = multipart("/api/v1/backups/restore")
                .file(new MockMultipartFile("file", "b.sgbackup", "application/octet-stream", file))
                .param("passphrase", passphrase);
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        return mvc.perform(request);
    }

    @Test
    void backupNeedsAPassphraseAndRecordsTheLastBackup() throws Exception {
        postJson("/api/v1/backups", owner, "{}").andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("PASSPHRASE_NOT_SET"));
        putJson("/api/v1/backups/passphrase", owner, "{\"passphrase\":\"short\"}").andExpect(status().isBadRequest());
        getJson("/api/v1/backups/info", owner).andExpect(jsonPath("$.lastBackupAt").doesNotExist());
        takeBackup();
        getJson("/api/v1/backups/info", device).andExpect(jsonPath("$.destination").value("Local folder"))
                .andExpect(jsonPath("$.lastBackupAt").exists());
        getJson("/api/v1/settings", owner).andExpect(jsonPath("$.backupPassphraseSet").value(true));
        getJson("/api/v1/backups", owner).andExpect(jsonPath("$", hasSize(1)));
        // Only the owner manages backups.
        getJson("/api/v1/backups", device).andExpect(status().isForbidden());
        postJson("/api/v1/backups", device, "{}").andExpect(status().isForbidden());
    }

    @Test
    void restoreBringsEverythingBackOnAFreshInstallAndWorkersNeedFaces() throws Exception {
        byte[] file = takeBackup();
        String beforeAudit = getJson("/api/v1/audit/verify", owner).andReturn().getResponse().getContentAsString();
        assertTrue(beforeAudit.contains("\"ok\":true"));

        // Not on a live install.
        restore(file, "correct horse battery", owner).andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("NOT_EMPTY"));

        wipeDatabase(); // a new phone: nothing there
        restore(file, "wrong passphrase", null).andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("BAD_PASSPHRASE"));
        assertEquals(0, jdbc.sql("SELECT COUNT(*) FROM workers").query(Integer.class).single());

        restore(file, "correct horse battery", null).andExpect(status().isOk())
                .andExpect(jsonPath("$.restored").value(true));

        // The old owner PIN works, history is intact, faces are gone.
        String again = login("owner", "123456");
        getJson("/api/v1/workers", again).andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].name").value("रमेश कुमार"))
                .andExpect(jsonPath("$[0].faceStatus").value("needsFace"));
        getJson("/api/v1/attendance/day?date=2026-10-24", again).andExpect(jsonPath("$", hasSize(2)));
        getJson("/api/v1/attendance/verify", again).andExpect(jsonPath("$.ok").value(true))
                .andExpect(jsonPath("$.checked").value(2));
        getJson("/api/v1/audit/verify", again).andExpect(jsonPath("$.ok").value(true));
        getJson("/api/v1/audit", again).andExpect(jsonPath("$[0].action").value("backup.restored"));

        // New marks continue the same chain.
        clock.advance(Duration.ofDays(1));
        postJson("/api/v1/attendance/face-marks", deviceToken(),
                "{\"workerId\":\"" + workerId + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}")
                .andExpect(status().isCreated());
        getJson("/api/v1/attendance/verify", again).andExpect(jsonPath("$.ok").value(true))
                .andExpect(jsonPath("$.checked").value(3));
    }

    @Test
    void aBackupMadeFromTamperedRecordsIsRefusedAndNothingIsLoaded() throws Exception {
        jdbc.sql("UPDATE attendance_events SET on_time = FALSE WHERE seq = 1").update(); // tamper
        byte[] file = takeBackup();
        wipeDatabase();
        restore(file, "correct horse battery", null).andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("BACKUP_TAMPERED"));
        assertEquals(0, jdbc.sql("SELECT COUNT(*) FROM workers").query(Integer.class).single(), "rolled back");
        assertEquals(0, jdbc.sql("SELECT COUNT(*) FROM users").query(Integer.class).single());
    }

    @Test
    void damagedAndForeignFilesAreRefusedCleanly() throws Exception {
        byte[] file = takeBackup();
        wipeDatabase();
        byte[] damaged = file.clone();
        damaged[damaged.length - 3] ^= 0x10;
        restore(damaged, "correct horse battery", null).andExpect(status().isUnprocessableEntity());
        restore("not a backup at all, just text of some length....".getBytes(), "whatever1", null)
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("BACKUP_CORRUPT"));
        restore(new byte[0], "whatever1", null).andExpect(status().isUnprocessableEntity());
        // The install is still pristine and usable afterwards.
        getJson("/api/v1/setup/status", null).andExpect(jsonPath("$.hasOwner").value(false));
    }

    @Test
    void conversionOfBackupValuesIsTypeSafe() {
        assertEquals(java.util.UUID.fromString("00000000-0000-7000-8000-000000000001"),
                BackupService.convert("UUID", "00000000-0000-7000-8000-000000000001"));
        assertEquals(5, BackupService.convert("INTEGER", 5));
        assertEquals(5L, BackupService.convert("BIGINT", "5"));
        assertEquals(true, BackupService.convert("BOOLEAN", "true"));
        assertEquals(0.5, BackupService.convert("DOUBLE PRECISION", 0.5));
        assertEquals("x", BackupService.convert("CHARACTER VARYING", "x"));
        assertEquals(null, BackupService.convert("UUID", null));
    }
}
