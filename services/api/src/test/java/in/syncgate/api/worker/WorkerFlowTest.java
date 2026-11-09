package in.syncgate.api.worker;

import static org.hamcrest.Matchers.hasSize;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.common.Uuid7;
import in.syncgate.api.support.ApiTest;
import org.junit.jupiter.api.Test;

class WorkerFlowTest extends ApiTest {

    static String shiftJson(String name) {
        return "{\"name\":\"" + name + "\",\"startMinute\":360,\"endMinute\":840,\"graceMinutes\":10,\"weeklyOff\":7}";
    }

    static String workerJson(String code, String name, String dob, String shiftId) {
        return "{\"code\":\"" + code + "\",\"name\":\"" + name + "\",\"dateOfBirth\":\"" + dob
                + "\",\"department\":\"Weaving\",\"designation\":\"Operator\",\"shiftId\":\"" + shiftId
                + "\",\"language\":\"hi\"}";
    }

    @Test
    void setupWindowAllowsFirstShiftAndWorkerOnlyUntilTheOwnerExists() throws Exception {
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, null, shiftJson("Day")).andExpect(status().isOk());
        postJson("/api/v1/workers", null, workerJson("W-0101", "Ramesh Kumar", "1990-05-01", shiftId))
                .andExpect(status().isCreated());
        // The setup window cannot delete or read audit data.
        deleteJson("/api/v1/workers/" + Uuid7.next(), null).andExpect(status().isForbidden());

        createOwner("123456");
        putJson("/api/v1/shifts/" + shiftId, null, shiftJson("Day")).andExpect(status().isUnauthorized());
        getJson("/api/v1/workers", null).andExpect(status().isUnauthorized());
    }

    @Test
    void enrolValidatesAgeCodeAndShift() throws Exception {
        String owner = createOwner("123456");
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner, shiftJson("Day")).andExpect(status().isOk());

        postJson("/api/v1/workers", owner, workerJson("W-0101", "Asha Devi", "2010-01-01", shiftId))
                .andExpect(status().isUnprocessableEntity()).andExpect(jsonPath("$.code").value("WORKER_UNDER_AGE"));
        // Turns 18 tomorrow: still blocked today (2026-10-24).
        postJson("/api/v1/workers", owner, workerJson("W-0101", "Asha Devi", "2008-10-25", shiftId))
                .andExpect(status().isUnprocessableEntity());
        postJson("/api/v1/workers", owner, workerJson("W-0101", "Asha Devi", "2008-10-24", shiftId))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.faceStatus").value("needsFace"))
                .andExpect(jsonPath("$.active").value(true));
        postJson("/api/v1/workers", owner, workerJson("w-0101", "Other", "1990-01-01", shiftId))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("DUPLICATE_WORKER_CODE"));
        postJson("/api/v1/workers", owner, workerJson("W-0102", "Other", "1990-01-01", Uuid7.next().toString()))
                .andExpect(status().isBadRequest());
        postJson("/api/v1/workers", owner, workerJson("bad code!", "Other", "1990-01-01", shiftId))
                .andExpect(status().isBadRequest());
        postJson("/api/v1/workers", owner, "{\"code\":\"W-9\"}").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION"));

        getJson("/api/v1/workers/next-code", owner).andExpect(jsonPath("$.code").value("W-0102"));
        getJson("/api/v1/workers/code-unique?code=W-0101", owner).andExpect(jsonPath("$.unique").value(false));
        getJson("/api/v1/workers/code-unique?code=W-0777", owner).andExpect(jsonPath("$.unique").value(true));
        getJson("/api/v1/departments", owner).andExpect(jsonPath("$", hasSize(1)));
    }

    @Test
    void rolesAreEnforced() throws Exception {
        String owner = createOwner("123456");
        String device = deviceToken();
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner, shiftJson("Day")).andExpect(status().isOk());
        String workerId = read(postJson("/api/v1/workers", owner, workerJson("W-0101", "Ramesh", "1990-05-01", shiftId))
                .andExpect(status().isCreated()), "$.id");

        // The gate phone reads, but cannot enrol, edit shifts or erase.
        getJson("/api/v1/workers", device).andExpect(status().isOk()).andExpect(jsonPath("$", hasSize(1)));
        postJson("/api/v1/workers", device, workerJson("W-0102", "X", "1990-01-01", shiftId))
                .andExpect(status().isForbidden());
        putJson("/api/v1/shifts/" + shiftId, device, shiftJson("Hack")).andExpect(status().isForbidden());
        deleteJson("/api/v1/workers/" + workerId, device).andExpect(status().isForbidden());

        // An admin may enrol but not erase (owner only).
        var users = getJson("/api/v1/users", owner).andReturn().getResponse().getContentAsString();
        String adminId = com.jayway.jsonpath.JsonPath.<java.util.List<String>>read(users, "$[?(@.role=='admin')].id")
                .get(0);
        putJson("/api/v1/users/" + adminId + "/pin", owner, "{\"pin\":\"234567\"}").andExpect(status().isNoContent());
        String admin = login("admin", "234567");
        postJson("/api/v1/workers", admin, workerJson("W-0102", "Sita", "1991-02-02", shiftId))
                .andExpect(status().isCreated());
        deleteJson("/api/v1/workers/" + workerId, admin).andExpect(status().isForbidden());
        deleteJson("/api/v1/workers/" + workerId, owner).andExpect(status().isNoContent());
        getJson("/api/v1/workers/" + workerId, owner).andExpect(status().isNotFound());
    }

    @Test
    void faceStatusActiveAndConsentWork() throws Exception {
        String owner = createOwner("123456");
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner, shiftJson("Day")).andExpect(status().isOk());
        String id = read(postJson("/api/v1/workers", owner, workerJson("W-0101", "Ramesh", "1990-05-01", shiftId)),
                "$.id");

        getJson("/api/v1/consents/" + id, owner).andExpect(jsonPath("$.hasConsent").value(false));
        postJson("/api/v1/consents", owner,
                "{\"workerId\":\"" + id + "\",\"noticeVersion\":\"v1\",\"language\":\"hi\",\"adminId\":\"Owner\"}")
                .andExpect(status().isNoContent());
        getJson("/api/v1/consents/" + id, owner).andExpect(jsonPath("$.hasConsent").value(true));

        putJson("/api/v1/workers/" + id + "/face-status", owner, "{\"status\":\"enrolled\"}")
                .andExpect(status().isNoContent());
        putJson("/api/v1/workers/" + id + "/face-status", owner, "{\"status\":\"bogus\"}")
                .andExpect(status().isBadRequest());
        putJson("/api/v1/workers/" + id + "/active", owner, "{\"active\":false}").andExpect(status().isNoContent());
        getJson("/api/v1/workers/" + id, owner).andExpect(jsonPath("$.faceStatus").value("enrolled"))
                .andExpect(jsonPath("$.active").value(false));
    }


    @Test
    void lastWizardStepsKeepSavingProgressAfterTheOwnerExists() throws Exception {
        String owner = createOwner("123456");
        String base = getJson("/api/v1/settings", owner).andExpect(jsonPath("$.mode").value("setup"))
                .andReturn().getResponse().getContentAsString();
        // Step 7 (first worker) is saved while the mode is still setup: allowed.
        putJson("/api/v1/settings", owner, base.replace("\"setupStep\":1", "\"setupStep\":7"))
                .andExpect(status().isNoContent());
        getJson("/api/v1/settings", owner).andExpect(jsonPath("$.setupStep").value(7));
        // Finishing setup is one way: the same request is refused once the mode is gate.
        putJson("/api/v1/settings", owner, base.replace("\"mode\":\"setup\"", "\"mode\":\"gate\""))
                .andExpect(status().isNoContent());
        putJson("/api/v1/settings", owner, base).andExpect(status().isConflict());
    }
    @Test
    void settingsGateDeviceMayOnlyChangeModeAndSetupIsOneWay() throws Exception {
        String owner = createOwner("123456");
        String device = deviceToken();
        String base = getJson("/api/v1/settings", owner).andExpect(jsonPath("$.mode").value("setup"))
                .andReturn().getResponse().getContentAsString();
        String cooldown = "\"cooldownSeconds\":120";

        putJson("/api/v1/settings", device, base.replace("\"mode\":\"setup\"", "\"mode\":\"gate\"")
                .replace(cooldown, "\"cooldownSeconds\":60")).andExpect(status().isNoContent());
        getJson("/api/v1/settings", owner).andExpect(jsonPath("$.mode").value("gate"))
                .andExpect(jsonPath("$.cooldownSeconds").value(120)); // device could not change it

        putJson("/api/v1/settings", owner, base.replace("\"mode\":\"setup\"", "\"mode\":\"gate\"")
                .replace(cooldown, "\"cooldownSeconds\":90")).andExpect(status().isNoContent());
        getJson("/api/v1/settings", owner).andExpect(jsonPath("$.cooldownSeconds").value(90));

        putJson("/api/v1/settings", owner, base).andExpect(status().isConflict()); // back to setup refused
        putJson("/api/v1/settings", owner, base.replace("\"mode\":\"setup\"", "\"mode\":\"gate\"")
                .replace(cooldown, "\"cooldownSeconds\":5")).andExpect(status().isBadRequest());
    }
}
