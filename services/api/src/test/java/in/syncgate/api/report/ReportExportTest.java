package in.syncgate.api.report;

import static org.hamcrest.Matchers.hasSize;
import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.common.Uuid7;
import in.syncgate.api.support.ApiTest;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.YearMonth;
import java.util.List;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;

class ReportExportTest extends ApiTest {

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
        workerId = addWorker("W-0101", "Ramesh Kumar", shiftId);
        addWorker("W-0102", "=cmd|' /C calc'!A0", shiftId);
    }

    String addWorker(String code, String name, String shiftId) throws Exception {
        String id = read(postJson("/api/v1/workers", owner,
                "{\"code\":\"" + code + "\",\"name\":\"" + name.replace("\"", "\\\"") + "\",\"dateOfBirth\":\"1990-05-01\","
                        + "\"department\":\"Weaving\",\"designation\":\"Operator\",\"shiftId\":\"" + shiftId
                        + "\",\"language\":\"hi\"}"), "$.id");
        putJson("/api/v1/workers/" + id + "/face-status", owner, "{\"status\":\"enrolled\"}");
        return id;
    }

    void face() throws Exception {
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + workerId + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}")
                .andExpect(status().isCreated());
    }

    @Test
    void monthlyMusterCountsPresentLateAbsentWeeklyOffAndOvertime() throws Exception {
        face(); // Sat 24-10 05:52 IN, on time
        clock.set("2026-10-24T15:30:00+05:30"); // 9.6 h later: 1.5 h overtime (shift is 8 h)
        face();
        clock.set("2026-10-26T06:30:00+05:30"); // Monday, late
        face();
        clock.set("2026-10-27T10:00:00+05:30");

        String body = getJson("/api/v1/reports/monthly?month=2026-10", owner).andExpect(jsonPath("$", hasSize(2)))
                .andReturn().getResponse().getContentAsString();
        // Ramesh sorts before the formula-looking name ('=' sorts first), so find him by code.
        List<String> days = com.jayway.jsonpath.JsonPath.<List<List<String>>>read(body, "$[?(@.worker.code=='W-0101')].days").get(0);
        assertEquals(31, days.size());
        assertEquals("P", days.get(23)); // 24th
        assertEquals("WO", days.get(24)); // Sunday 25th
        assertEquals("L", days.get(25)); // Monday 26th, late
        assertEquals("", days.get(26)); // Tue 27th is today and the day is not over, so no absence yet
        assertEquals("", days.get(27)); // 28th is in the future

        getJson("/api/v1/reports/monthly?month=2026-10", owner)
                .andExpect(jsonPath("$[?(@.worker.code=='W-0101')].present", org.hamcrest.Matchers.hasItem(2)))
                .andExpect(jsonPath("$[?(@.worker.code=='W-0101')].late", org.hamcrest.Matchers.hasItem(1)))
                .andExpect(jsonPath("$[?(@.worker.code=='W-0101')].overtimeHours", org.hamcrest.Matchers.hasItem(1.5)));
        // The other worker never came: 24th, 26th are absent; the 25th is a Sunday.
        getJson("/api/v1/reports/monthly?month=2026-10", owner)
                .andExpect(jsonPath("$[?(@.worker.code=='W-0102')].absent", org.hamcrest.Matchers.hasItem(2)));
    }

    @Test
    void monthWithNoMarksIsEmptyAndFiltersApply() throws Exception {
        getJson("/api/v1/reports/monthly?month=2026-09", owner).andExpect(jsonPath("$", hasSize(0)));
        face();
        getJson("/api/v1/reports/monthly?month=2026-10&department=Nope", owner).andExpect(jsonPath("$", hasSize(0)));
        getJson("/api/v1/reports/monthly?month=2026-10&department=Weaving", owner).andExpect(jsonPath("$", hasSize(2)));
        getJson("/api/v1/reports/monthly?month=oct", owner).andExpect(status().isBadRequest());
        getJson("/api/v1/reports/working-days?month=2026-10", owner).andExpect(jsonPath("$.days").value(21));
    }

    @Test
    void dailyViewShowsInOutAndFlagsManualMarks() throws Exception {
        face();
        clock.advance(Duration.ofHours(4));
        face();
        getJson("/api/v1/reports/daily?date=2026-10-24", owner)
                .andExpect(jsonPath("$[?(@.worker.code=='W-0101')].status", org.hamcrest.Matchers.hasItem("HD"))) // only 4 h worked
                .andExpect(jsonPath("$[?(@.worker.code=='W-0102')].status", org.hamcrest.Matchers.hasItem("A")));
    }

    @Test
    void reportsAreForAdminsNotTheGatePhone() throws Exception {
        getJson("/api/v1/reports/monthly?month=2026-10", device).andExpect(status().isForbidden());
        mvc.perform(post("/api/v1/exports").header("Authorization", "Bearer " + device)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"format\":\"csv\",\"month\":\"2026-10\"}")).andExpect(status().isForbidden());
    }

    @Test
    void csvExportIsUtf8WithBomQuotedAndDefusesFormulas() throws Exception {
        face();
        var result = mvc.perform(post("/api/v1/exports").header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"format\":\"csv\",\"month\":\"2026-10\"}"))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Row-Count", "2"))
                .andExpect(header().string("Content-Disposition", org.hamcrest.Matchers.containsString("SyncGate_Muster_2026-10.csv")))
                .andReturn().getResponse();
        byte[] bytes = result.getContentAsByteArray();
        String text = new String(bytes, StandardCharsets.UTF_8);
        assertTrue(text.startsWith("﻿Worker ID,Name,Department"));
        assertTrue(text.contains("24-10-2026"), "dates are DD-MM-YYYY");
        assertTrue(text.contains("\"'=cmd|' /C calc'!A0\"") || text.contains("'=cmd|' /C calc'!A0"),
                "a name starting with = must be neutralised: " + text);
        assertTrue(text.contains("\r\n"));
        assertEquals(ExportService.sha256(bytes), result.getHeader("X-Content-Sha256"));
        // Same data, same bytes.
        var again = mvc.perform(post("/api/v1/exports").header("Authorization", "Bearer " + owner)
                .contentType(MediaType.APPLICATION_JSON).content("{\"format\":\"csv\",\"month\":\"2026-10\"}"))
                .andReturn().getResponse().getContentAsByteArray();
        assertArrayEquals(bytes, again);
        getJson("/api/v1/audit", owner).andExpect(jsonPath("$[0].action").value("export.created"));
    }

    @Test
    void excelExportOpensAndHoldsRealCellsNotFormulas() throws Exception {
        face();
        byte[] bytes = mvc.perform(post("/api/v1/exports").header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"format\":\"excel\",\"month\":\"2026-10\"}"))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", org.hamcrest.Matchers.containsString("spreadsheetml")))
                .andReturn().getResponse().getContentAsByteArray();
        try (XSSFWorkbook book = new XSSFWorkbook(new ByteArrayInputStream(bytes))) {
            assertEquals(List.of("Muster", "Summary", "Exceptions", "About"),
                    List.of(book.getSheetName(0), book.getSheetName(1), book.getSheetName(2), book.getSheetName(3)));
            var sheet = book.getSheetAt(0);
            assertEquals("Worker ID", sheet.getRow(0).getCell(0).getStringCellValue());
            assertEquals(3, sheet.getPhysicalNumberOfRows());
            boolean sawFormulaName = false;
            for (int r = 1; r <= 2; r++) {
                var cell = sheet.getRow(r).getCell(1);
                assertEquals(org.apache.poi.ss.usermodel.CellType.STRING, cell.getCellType());
                sawFormulaName |= cell.getStringCellValue().startsWith("=cmd");
            }
            assertTrue(sawFormulaName, "formula-looking text is stored as plain text");
            assertEquals(YearMonth.of(2026, 10).toString(), book.getSheet("About").getRow(0).getCell(1).getStringCellValue());
        }
    }

    @Test
    void csvCellEscaping() {
        assertEquals("plain", ExportService.csvCell("plain"));
        assertEquals("\"a,b\"", ExportService.csvCell("a,b"));
        assertEquals("\"say \"\"hi\"\"\"", ExportService.csvCell("say \"hi\""));
        assertEquals("'=1+1", ExportService.csvCell("=1+1"));
        assertEquals("'@SUM(A1)", ExportService.csvCell("@SUM(A1)"));
        assertEquals("'-5", ExportService.csvCell("-5"));
        assertEquals("", ExportService.csvCell(null));
    }

    @Test
    void overtimeRoundsDownToHalfHoursAndIgnoresShortExtras() {
        assertEquals(0.0, ReportService.overtime(Duration.ofHours(8).plusMinutes(20), 8));
        assertEquals(0.5, ReportService.overtime(Duration.ofHours(8).plusMinutes(40), 8));
        assertEquals(1.5, ReportService.overtime(Duration.ofHours(9).plusMinutes(50), 8));
        assertEquals(0.0, ReportService.overtime(Duration.ofHours(6), 8));
    }
}
