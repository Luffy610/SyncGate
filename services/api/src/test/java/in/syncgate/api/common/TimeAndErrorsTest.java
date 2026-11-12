package in.syncgate.api.common;

import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.support.ApiTest;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class TimeAndErrorsTest extends ApiTest {

    @Test
    void serverTimeIsTheDemoClockAndNeedsATokenOnceSetUp() throws Exception {
        // During first-run setup the app has no credentials yet.
        getJson("/api/v1/time", null).andExpect(status().isOk())
                .andExpect(jsonPath("$.now").value("2026-10-24T00:22:00Z"));
        createOwner("123456");
        getJson("/api/v1/time", null).andExpect(status().isUnauthorized());
        getJson("/api/v1/time", deviceToken()).andExpect(status().isOk());
    }

    @Test
    void errorsNeverLeakInternals() throws Exception {
        String owner = createOwner("123456");
        // Malformed JSON, wrong content type, huge ids, SQL-looking input.
        postJson("/api/v1/workers", owner, "{not json").andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION"))
                .andExpect(content().string(not(containsString("Exception"))))
                .andExpect(content().string(not(containsString("jackson"))));
        mvc.perform(post("/api/v1/workers").header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.TEXT_PLAIN).content("x"))
                .andExpect(status().isUnsupportedMediaType());
        getJson("/api/v1/workers/' OR 1=1 --", owner).andExpect(status().isNotFound())
                .andExpect(content().string(not(containsString("SQL"))));
        getJson("/api/v1/workers/code-unique?code=%27%3B%20DROP%20TABLE%20workers%3B--", owner)
                .andExpect(status().isOk()).andExpect(jsonPath("$.unique").value(true));
        getJson("/api/v1/workers", owner).andExpect(status().isOk()); // table still there
    }

    @Test
    void controlCharactersInNamesAreStripped() throws Exception {
        String owner = createOwner("123456");
        String shiftId = in.syncgate.api.common.Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner,
                "{\"name\":\"Day\",\"startMinute\":360,\"endMinute\":840,\"graceMinutes\":10,\"weeklyOff\":7}");
        postJson("/api/v1/workers", owner,
                "{\"code\":\"W-1\",\"name\":\"Ra\\u0000me\\nsh\\u0007\",\"dateOfBirth\":\"1990-05-01\","
                        + "\"department\":\"A\",\"designation\":\"B\",\"shiftId\":\"" + shiftId + "\",\"language\":\"en\"}")
                .andExpect(status().isCreated()).andExpect(jsonPath("$.name").value("Ra me sh"));
    }
}
