package in.syncgate.api.support;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;

import com.jayway.jsonpath.JsonPath;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.user.UserService;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import org.junit.jupiter.api.BeforeEach;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * Base for end-to-end API tests. Every test class gets a fresh application
 * context and an empty in-memory database, and a clock the test can move.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Import(ApiTest.TestClockConfig.class)
public abstract class ApiTest {

    public static final String DEVICE_KEY = "test-device-key-0001";

    /** A clock tests can move. It starts at the demo time. */
    public static class MutableClock implements AppClock {
        private volatile Instant now = OffsetDateTime.parse("2026-10-24T05:52:00+05:30").toInstant();

        @Override
        public Instant now() {
            return now;
        }

        @Override
        public ZoneId zone() {
            return ZoneId.of("Asia/Kolkata");
        }

        public void set(String isoOffset) {
            now = OffsetDateTime.parse(isoOffset).toInstant();
        }

        public void advance(Duration by) {
            now = now.plus(by);
        }
    }

    @TestConfiguration
    static class TestClockConfig {
        @Bean
        @Primary
        MutableClock testClock() {
            return new MutableClock();
        }
    }

    @Autowired protected MockMvc mvc;
    @Autowired protected MutableClock clock;

    @Autowired private JdbcClient jdbc;
    @Autowired private UserService userService;

    private static final String[] TABLES = {
        "exceptions", "attendance_events", "consents", "workers", "shifts", "departments", "users",
        "audit_log", "chain_heads", "licence", "issued_licence_keys", "backups", "backup_key", "exports",
        "app_settings"
    };

    /** Every test starts from a blank database and the demo clock. */
    @BeforeEach
    void resetState() {
        for (String table : TABLES) {
            jdbc.sql("DELETE FROM " + table).update();
        }
        ReflectionTestUtils.setField(userService, "ownerExists", false);
        clock.set("2026-10-24T05:52:00+05:30");
    }

    // ---- auth helpers ------------------------------------------------------

    protected String deviceToken() throws Exception {
        return token(post("/api/v1/auth/device").contentType(MediaType.APPLICATION_JSON)
                .content("{\"deviceKey\":\"" + DEVICE_KEY + "\"}"));
    }

    /** Creates the owner (first run) and returns the owner's token. */
    protected String createOwner(String pin) throws Exception {
        return token(post("/api/v1/auth/owner").contentType(MediaType.APPLICATION_JSON)
                .content("{\"pin\":\"" + pin + "\"}"));
    }

    protected String login(String role, String pin) throws Exception {
        return token(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                .content("{\"role\":\"" + role + "\",\"pin\":\"" + pin + "\"}"));
    }

    private String token(MockHttpServletRequestBuilder request) throws Exception {
        String body = mvc.perform(request).andReturn().getResponse().getContentAsString();
        return JsonPath.read(body, "$.token");
    }

    // ---- request helpers ---------------------------------------------------

    protected ResultActions getJson(String path, String token) throws Exception {
        return mvc.perform(auth(get(path), token));
    }

    protected ResultActions postJson(String path, String token, String body) throws Exception {
        return mvc.perform(auth(post(path), token).contentType(MediaType.APPLICATION_JSON).content(body));
    }

    protected ResultActions putJson(String path, String token, String body) throws Exception {
        return mvc.perform(auth(put(path), token).contentType(MediaType.APPLICATION_JSON).content(body));
    }

    protected ResultActions deleteJson(String path, String token) throws Exception {
        return mvc.perform(auth(delete(path), token));
    }

    protected static MockHttpServletRequestBuilder auth(MockHttpServletRequestBuilder builder, String token) {
        return token == null ? builder : builder.header("Authorization", "Bearer " + token);
    }

    protected static String read(ResultActions result, String jsonPath) throws Exception {
        Object value = JsonPath.read(result.andReturn().getResponse().getContentAsString(), jsonPath);
        return String.valueOf(value);
    }
}
