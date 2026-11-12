package in.syncgate.api.licence;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.support.ApiTest;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;

class LicenceFlowTest extends ApiTest {

    @Autowired LicenceService licence;

    @Test
    void noLicenceThenTrialThenRestrictedAfterThirtyDays() throws Exception {
        String owner = createOwner("123456");
        getJson("/api/v1/licence", owner).andExpect(jsonPath("$.state").value("none"));
        postJson("/api/v1/licence/trial", owner, "{}").andExpect(jsonPath("$.state").value("trial"))
                .andExpect(jsonPath("$.expiresOn").value("2026-11-23"));
        postJson("/api/v1/licence/trial", owner, "{}").andExpect(jsonPath("$.state").value("trial")); // idempotent
        clock.advance(Duration.ofDays(31));
        getJson("/api/v1/licence", owner).andExpect(jsonPath("$.state").value("restricted"));
    }

    @Test
    void activationValidatesTheKeyFormatAndReportsOffline() throws Exception {
        String owner = createOwner("123456");
        postJson("/api/v1/licence/activate", owner, "{\"key\":\"nonsense\"}").andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.code").value("INVALID_LICENCE_KEY"));
        postJson("/api/v1/licence/activate", owner, "{\"key\":\"SGT-NONE-T123-4567\"}")
                .andExpect(status().isServiceUnavailable()).andExpect(jsonPath("$.code").value("NO_INTERNET"));
        postJson("/api/v1/licence/activate", owner, "{\"key\":\"sgt-4f7k-2q9m-a1b2\"}").andExpect(status().isOk())
                .andExpect(jsonPath("$.state").value("active")).andExpect(jsonPath("$.key").value("SGT-4F7K-2Q9M-A1B2"))
                .andExpect(jsonPath("$.expiresOn").value("2027-10-24"));
    }

    @Test
    void activeThenGraceThenRestrictedByDate() throws Exception {
        String owner = createOwner("123456");
        postJson("/api/v1/licence/activate", owner, "{\"key\":\"SGT-4F7K-2Q9M-A1B2\"}");
        clock.advance(Duration.ofDays(366));
        getJson("/api/v1/licence", owner).andExpect(jsonPath("$.state").value("graceOverdue"));
        clock.advance(Duration.ofDays(31));
        getJson("/api/v1/licence", owner).andExpect(jsonPath("$.state").value("restricted"));
        // Even restricted, export and backup endpoints are not blocked by licence state.
        getJson("/api/v1/reports/monthly?month=2026-10", owner).andExpect(status().isOk());
    }

    @Test
    void tokenIsSignedAndTamperProof() throws Exception {
        String owner = createOwner("123456");
        postJson("/api/v1/licence/activate", owner, "{\"key\":\"SGT-4F7K-2Q9M-A1B2\"}");
        String token = licence.storedToken();
        assertTrue(licence.verify(token));
        String[] parts = token.split("\\.");
        String forgedPayload = java.util.Base64.getUrlEncoder().withoutPadding()
                .encodeToString("{\"lic\":\"x\",\"exp\":\"2099-01-01\"}".getBytes());
        assertFalse(licence.verify(parts[0] + "." + forgedPayload + "." + parts[2]));
        assertFalse(licence.verify("garbage"));
        assertFalse(licence.verify(null));
        assertEquals(32, licence.publicKey().length);
    }

    @Test
    void onlyTheOwnerOrSetupCanChangeTheLicenceButTheGateCanRead() throws Exception {
        // First run: the wizard has no credentials yet.
        postJson("/api/v1/licence/activate", null, "{\"key\":\"SGT-4F7K-2Q9M-A1B2\"}").andExpect(status().isOk());
        String owner = createOwner("123456");
        String device = deviceToken();
        getJson("/api/v1/licence", device).andExpect(status().isOk());
        postJson("/api/v1/licence/activate", device, "{\"key\":\"SGT-4F7K-2Q9M-A1B3\"}").andExpect(status().isForbidden());
        postJson("/api/v1/licence/activate", null, "{\"key\":\"SGT-4F7K-2Q9M-A1B3\"}").andExpect(status().isUnauthorized());
        postJson("/api/v1/licence/checkin", owner, "{}").andExpect(status().isOk());
    }
}
