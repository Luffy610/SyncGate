package in.syncgate.api.tally;

import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import in.syncgate.api.common.Uuid7;
import in.syncgate.api.support.ApiTest;
import java.io.ByteArrayInputStream;
import java.time.Duration;
import javax.xml.parsers.DocumentBuilderFactory;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.w3c.dom.Document;
import org.w3c.dom.NodeList;

class TallyFlowTest extends ApiTest {

    String owner;
    String device;
    String ramesh;
    String sita;

    @BeforeEach
    void seed() throws Exception {
        owner = createOwner("123456");
        device = deviceToken();
        String shiftId = Uuid7.next().toString();
        putJson("/api/v1/shifts/" + shiftId, owner,
                "{\"name\":\"Day\",\"startMinute\":360,\"endMinute\":840,\"graceMinutes\":10,\"weeklyOff\":7}");
        ramesh = worker("W-0101", "Ramesh Kumar", shiftId);
        sita = worker("W-0102", "Sita Devi", shiftId);
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + ramesh + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}");
    }

    String worker(String code, String name, String shiftId) throws Exception {
        String id = read(postJson("/api/v1/workers", owner,
                "{\"code\":\"" + code + "\",\"name\":\"" + name + "\",\"dateOfBirth\":\"1990-05-01\","
                        + "\"department\":\"Weaving\",\"designation\":\"Operator\",\"shiftId\":\"" + shiftId
                        + "\",\"language\":\"hi\"}"), "$.id");
        putJson("/api/v1/workers/" + id + "/face-status", owner, "{\"status\":\"enrolled\"}");
        return id;
    }

    byte[] tallyFile() throws Exception {
        return mvc.perform(post("/api/v1/exports").header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"format\":\"tally\",\"month\":\"2026-10\"}"))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsByteArray();
    }

    @Test
    void mappingAndMatchCaptionTrackWhoIsMapped() throws Exception {
        getJson("/api/v1/tally/match", owner).andExpect(jsonPath("$.matched").value(0))
                .andExpect(jsonPath("$.total").value(2));
        putJson("/api/v1/tally/mappings/" + ramesh, owner, "{\"name\":\"RAMESH KUMAR\"}")
                .andExpect(status().isNoContent());
        getJson("/api/v1/tally/match", owner).andExpect(jsonPath("$.matched").value(1));
        getJson("/api/v1/tally/mappings", owner).andExpect(jsonPath("$['" + ramesh + "']").value("RAMESH KUMAR"));
        // Changing a name replaces it.
        putJson("/api/v1/tally/mappings/" + ramesh, owner, "{\"name\":\"R KUMAR\"}").andExpect(status().isNoContent());
        getJson("/api/v1/tally/mappings", owner).andExpect(jsonPath("$['" + ramesh + "']").value("R KUMAR"));
        putJson("/api/v1/tally/mappings/" + sita, owner, "{\"name\":\"  \"}").andExpect(status().isBadRequest());
        putJson("/api/v1/tally/mappings/" + Uuid7.next(), owner, "{\"name\":\"X\"}").andExpect(status().isNotFound());
        getJson("/api/v1/audit", owner).andExpect(jsonPath("$[0].action").value("tally.mapped"));
    }

    @Test
    void onlyAdminsAndOwnersTouchTallyData() throws Exception {
        getJson("/api/v1/tally/mappings", device).andExpect(status().isForbidden());
        putJson("/api/v1/tally/mappings/" + ramesh, device, "{\"name\":\"X\"}").andExpect(status().isForbidden());
        getJson("/api/v1/tally/match", null).andExpect(status().isUnauthorized());
    }

    @Test
    void xmlHasTheTallyImportShapeAndOnlyMappedWorkers() throws Exception {
        putJson("/api/v1/tally/mappings/" + ramesh, owner, "{\"name\":\"RAMESH KUMAR\"}");
        clock.set("2026-10-24T15:30:00+05:30");
        postJson("/api/v1/attendance/face-marks", device,
                "{\"workerId\":\"" + ramesh + "\",\"score\":0.9,\"margin\":0.2,\"liveness\":0.9}");
        clock.set("2026-10-27T10:00:00+05:30");

        var response = mvc.perform(post("/api/v1/exports").header("Authorization", "Bearer " + owner)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"format\":\"tally\",\"month\":\"2026-10\"}"))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", containsString("application/xml")))
                .andExpect(header().string("Content-Disposition", containsString("SyncGate_Tally_2026-10.xml")))
                .andExpect(header().string("X-Row-Count", "1"))
                .andExpect(header().string("X-Unmapped", "1"))
                .andReturn().getResponse();

        Document doc = DocumentBuilderFactory.newInstance().newDocumentBuilder()
                .parse(new ByteArrayInputStream(response.getContentAsByteArray()));
        assertEquals("ENVELOPE", doc.getDocumentElement().getTagName());
        assertEquals("Import Data", doc.getElementsByTagName("TALLYREQUEST").item(0).getTextContent());
        assertEquals("Vouchers", doc.getElementsByTagName("REPORTNAME").item(0).getTextContent());
        var voucher = doc.getElementsByTagName("VOUCHER").item(0);
        assertEquals("Attendance", voucher.getAttributes().getNamedItem("VCHTYPE").getNodeValue());
        assertEquals("20261031", doc.getElementsByTagName("DATE").item(0).getTextContent());

        NodeList entries = doc.getElementsByTagName("ATTENDANCEENTRIES.LIST");
        assertEquals(3, entries.getLength(), "present, absent, overtime for the one mapped employee");
        String all = new String(response.getContentAsByteArray(), java.nio.charset.StandardCharsets.UTF_8);
        assertTrue(all.contains("RAMESH KUMAR"));
        assertTrue(!all.contains("SITA DEVI") && !all.contains("Sita"), "unmapped worker is left out");
        assertTrue(all.contains("<ATTENDANCETYPE>Present Days</ATTENDANCETYPE><ATTDTYPEVALUE>2</ATTDTYPEVALUE>")
                || all.contains("Present Days"));
        assertTrue(all.contains("<ATTENDANCETYPE>Overtime Hours</ATTENDANCETYPE><ATTDTYPEVALUE>1.5</ATTDTYPEVALUE>"),
                all);
    }

    @Test
    void namesWithXmlSpecialCharactersAreEscapedAndStillParse() throws Exception {
        putJson("/api/v1/tally/mappings/" + ramesh, owner, "{\"name\":\"A & B <Traders> \\\"Co\\\"\"}");
        byte[] xml = tallyFile();
        Document doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(new ByteArrayInputStream(xml));
        assertEquals("A & B <Traders> \"Co\"", doc.getElementsByTagName("EMPLOYEENAME").item(0).getTextContent());
        String raw = new String(xml, java.nio.charset.StandardCharsets.UTF_8);
        assertTrue(raw.contains("A &amp; B &lt;Traders&gt;"));
    }

    @Test
    void erasingAWorkerDropsTheirTallyNameAndBackupsKeepMappings() throws Exception {
        putJson("/api/v1/tally/mappings/" + ramesh, owner, "{\"name\":\"RAMESH KUMAR\"}");
        putJson("/api/v1/tally/mappings/" + sita, owner, "{\"name\":\"SITA DEVI\"}");

        // Mapping survives a backup and restore.
        putJson("/api/v1/backups/passphrase", owner, "{\"passphrase\":\"correct horse battery\"}");
        String id = read(postJson("/api/v1/backups", owner, "{}"), "$.id");
        byte[] file = mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                        .get("/api/v1/backups/" + id + "/download").header("Authorization", "Bearer " + owner))
                .andReturn().getResponse().getContentAsByteArray();
        wipeDatabase();
        mvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart("/api/v1/backups/restore")
                        .file(new org.springframework.mock.web.MockMultipartFile("file", "b", "application/octet-stream", file))
                        .param("passphrase", "correct horse battery"))
                .andExpect(status().isOk());
        String again = login("owner", "123456");
        getJson("/api/v1/tally/mappings", again).andExpect(jsonPath("$['" + ramesh + "']").value("RAMESH KUMAR"));

        // Erasing Sita (no history) removes her mapping; Ramesh (has history) too.
        deleteJson("/api/v1/workers/" + sita, again).andExpect(status().isNoContent());
        deleteJson("/api/v1/workers/" + ramesh, again).andExpect(status().isNoContent());
        getJson("/api/v1/tally/mappings", again).andExpect(jsonPath("$.length()").value(0));
        clock.advance(Duration.ofSeconds(1));
    }
}
