package in.syncgate.api.user;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.support.ApiTest;
import java.time.Duration;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class AuthFlowTest extends ApiTest {

    @Test
    void setupStatusIsPublicAndOwnerCreationClosesTheSetupWindow() throws Exception {
        mvc.perform(get("/api/v1/setup/status")).andExpect(status().isOk())
                .andExpect(jsonPath("$.hasOwner").value(false));

        // Anonymous callers get only the narrow setup powers while no owner exists.
        mvc.perform(get("/api/v1/audit")).andExpect(status().isForbidden());

        mvc.perform(post("/api/v1/auth/owner").contentType(MediaType.APPLICATION_JSON).content("{\"pin\":\"123456\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.recoveryCode").value(org.hamcrest.Matchers.matchesPattern(
                        "[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}")))
                .andExpect(jsonPath("$.user.role").value("owner"));

        mvc.perform(get("/api/v1/setup/status")).andExpect(jsonPath("$.hasOwner").value(true));
        // The window is shut: an anonymous request is now simply unauthenticated.
        mvc.perform(get("/api/v1/workers")).andExpect(status().isUnauthorized());
        // And the owner cannot be created twice.
        mvc.perform(post("/api/v1/auth/owner").contentType(MediaType.APPLICATION_JSON).content("{\"pin\":\"654321\"}"))
                .andExpect(status().isConflict()).andExpect(jsonPath("$.code").value("SETUP_DONE"));
    }

    @Test
    void pinMustBeSixDigits() throws Exception {
        for (String bad : new String[] {"12345", "1234567", "abcdef", "12 456", ""}) {
            mvc.perform(post("/api/v1/auth/owner").contentType(MediaType.APPLICATION_JSON)
                            .content("{\"pin\":\"" + bad + "\"}"))
                    .andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("VALIDATION"));
        }
    }

    @Test
    void loginWrongPinCountsDownThenLocksOutWithBackoff() throws Exception {
        createOwner("123456");
        String wrong = "{\"role\":\"owner\",\"pin\":\"000111\"}";
        for (int left = 4; left >= 1; left--) {
            int expected = left;
            mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(wrong))
                    .andExpect(status().isUnauthorized())
                    .andExpect(jsonPath("$.code").value("WRONG_PIN"))
                    .andExpect(jsonPath("$.details.attemptsLeft").value(expected));
        }
        // 5th wrong attempt locks for 30 s.
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(wrong))
                .andExpect(status().isUnauthorized()).andExpect(jsonPath("$.details.lockedForSeconds").value(30));
        // Even the right PIN is refused while locked.
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"role\":\"owner\",\"pin\":\"123456\"}"))
                .andExpect(status().isTooManyRequests()).andExpect(jsonPath("$.code").value("LOCKED_OUT"));
        // After the lock expires the right PIN works and clears the counter.
        clock.advance(Duration.ofSeconds(31));
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"role\":\"owner\",\"pin\":\"123456\"}"))
                .andExpect(status().isOk());
        // 6th failure after a clean slate starts counting from zero again.
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON).content(wrong))
                .andExpect(jsonPath("$.details.attemptsLeft").value(4));
    }

    @Test
    void lockoutPolicyMatchesTheFlutterPinPolicy() {
        assertEquals(Duration.ZERO, UserService.lockoutAfter(4));
        assertEquals(Duration.ofSeconds(30), UserService.lockoutAfter(5));
        assertEquals(Duration.ofSeconds(60), UserService.lockoutAfter(6));
        assertEquals(Duration.ofSeconds(120), UserService.lockoutAfter(7));
        assertEquals(Duration.ofMinutes(15), UserService.lockoutAfter(30));
    }

    @Test
    void adminAndGateOperatorHaveNoPinUntilTheOwnerSetsOne() throws Exception {
        String owner = createOwner("123456");
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"role\":\"admin\",\"pin\":\"234567\"}"))
                .andExpect(status().isUnauthorized());

        String users = getJson("/api/v1/users", owner).andExpect(jsonPath("$", hasSize(3)))
                .andReturn().getResponse().getContentAsString();
        String adminId = com.jayway.jsonpath.JsonPath.<java.util.List<String>>read(users,
                "$[?(@.role=='admin')].id").get(0);
        putJson("/api/v1/users/" + adminId + "/pin", owner, "{\"pin\":\"234567\"}").andExpect(status().isNoContent());
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"role\":\"admin\",\"pin\":\"234567\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.user.role").value("admin"));
    }

    @Test
    void recoveryCodeResetsTheOwnerPin() throws Exception {
        String body = mvc.perform(post("/api/v1/auth/owner").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"pin\":\"123456\"}")).andReturn().getResponse().getContentAsString();
        String code = com.jayway.jsonpath.JsonPath.read(body, "$.recoveryCode");

        mvc.perform(post("/api/v1/auth/reset-owner-pin").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recoveryCode\":\"AAAA-AAAA-AAAA\",\"newPin\":\"999999\"}"))
                .andExpect(status().isUnauthorized());
        mvc.perform(post("/api/v1/auth/reset-owner-pin").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"recoveryCode\":\"" + code.toLowerCase() + "\",\"newPin\":\"999999\"}"))
                .andExpect(status().isOk());
        mvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"role\":\"owner\",\"pin\":\"999999\"}"))
                .andExpect(status().isOk());
    }

    @Test
    void deviceKeyIssuesALimitedTokenAndWrongKeyIsRefused() throws Exception {
        mvc.perform(post("/api/v1/auth/device").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"deviceKey\":\"not-the-key-not-the-key\"}"))
                .andExpect(status().isUnauthorized());
        createOwner("123456");
        String device = deviceToken();
        getJson("/api/v1/setup/status", device).andExpect(status().isOk());
        // The gate device can read core data but cannot manage users.
        getJson("/api/v1/users", device).andExpect(status().isForbidden());
    }

    @Test
    void tamperedAndGarbageTokensAreRejectedAndHeadersAreHardened() throws Exception {
        String owner = createOwner("123456");
        getJson("/api/v1/users", owner + "x").andExpect(status().isUnauthorized());
        getJson("/api/v1/users", "not.a.jwt").andExpect(status().isUnauthorized());
        getJson("/api/v1/users", null).andExpect(status().isUnauthorized());
        getJson("/api/v1/users", owner).andExpect(status().isOk())
                .andExpect(header().string("X-Content-Type-Options", "nosniff"))
                .andExpect(header().string("X-Frame-Options", "DENY"))
                .andExpect(header().string("Content-Security-Policy", containsString("default-src 'none'")))
                .andExpect(header().string("Cache-Control", containsString("no-store")));
    }

    @Test
    void unknownRoutesAndMethodsLeakNothing() throws Exception {
        String owner = createOwner("123456");
        getJson("/api/v1/nothing-here", owner).andExpect(status().isNotFound());
        mvc.perform(get("/internal/secret")).andExpect(status().isUnauthorized());
        mvc.perform(get("/actuator/env")).andExpect(status().is4xxClientError());
        mvc.perform(get("/actuator/health")).andExpect(status().isOk());
    }
}
