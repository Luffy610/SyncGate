package in.syncgate.api.tally;

import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.ApiException;
import in.syncgate.api.domain.Enums.FaceStatus;
import in.syncgate.api.report.ReportService.MusterRow;
import in.syncgate.api.worker.WorkerService;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import javax.xml.stream.XMLOutputFactory;
import javax.xml.stream.XMLStreamException;
import javax.xml.stream.XMLStreamWriter;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Tally Prime payroll export (ADR-0015, FR-RPT-04): the mapping from each
 * worker to their Tally employee name, and the attendance import file. The
 * file is only ever written; the app never talks to a running Tally.
 *
 * <p>Workers without a mapping are left out of the file and counted, so the
 * owner can map them and export again. (ADR-0015 proposes blocking instead;
 * the app's design lets the export go ahead and shows "1 to map".) The XML
 * layout follows the ADR and still needs the manual import QA against a real
 * Tally Prime company that the ADR calls for.
 */
@Service
public class TallyService {

    static final DateTimeFormatter TALLY_DATE = DateTimeFormatter.ofPattern("yyyyMMdd");

    /** A file plus how many employees went in and how many workers were left out. */
    public record TallyFile(byte[] bytes, int employees, int unmapped) {}

    public record Match(int matched, int total) {}

    private final JdbcClient jdbc;
    private final WorkerService workers;
    private final AuditService audit;

    public TallyService(JdbcClient jdbc, WorkerService workers, AuditService audit) {
        this.jdbc = jdbc;
        this.workers = workers;
        this.audit = audit;
    }

    public Map<UUID, String> mappings() {
        Map<UUID, String> map = new LinkedHashMap<>();
        jdbc.sql("SELECT worker_id, tally_name FROM tally_mappings ORDER BY tally_name")
                .query((rs, i) -> {
                    map.put(rs.getObject(1, UUID.class), rs.getString(2));
                    return null;
                }).list();
        return map;
    }

    @Transactional
    public void set(UUID workerId, String name, String actor) {
        WorkerService.Worker worker = workers.require(workerId);
        String clean = name == null ? "" : name.replaceAll("\\p{Cntrl}", " ").strip().replaceAll("\\s{2,}", " ");
        if (clean.isEmpty() || clean.length() > 120) {
            throw ApiException.invalid("The Tally employee name must be 1 to 120 characters");
        }
        jdbc.sql("DELETE FROM tally_mappings WHERE worker_id = :w").param("w", workerId).update();
        jdbc.sql("INSERT INTO tally_mappings (worker_id, tally_name) VALUES (:w, :n)")
                .param("w", workerId).param("n", clean).update();
        audit.record(actor, "tally.mapped", worker.code());
    }

    /** Enrolled, active workers and how many already have a Tally name (design 16 caption). */
    public Match match() {
        Map<UUID, String> map = mappings();
        List<WorkerService.Worker> enrolled = workers.all().stream()
                .filter(w -> w.active() && w.faceStatus() == FaceStatus.ENROLLED).toList();
        int matched = (int) enrolled.stream().filter(w -> map.containsKey(w.id())).count();
        return new Match(matched, enrolled.size());
    }

    /**
     * One Attendance voucher dated the last day of the month. Each mapped
     * employee gets "Present Days", "Absent Days" and "Overtime Hours" entries.
     */
    public TallyFile build(List<MusterRow> rows, YearMonth month) {
        Map<UUID, String> map = mappings();
        int employees = 0;
        int unmapped = 0;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        try {
            XMLStreamWriter xml = XMLOutputFactory.newFactory().createXMLStreamWriter(out, "UTF-8");
            xml.writeStartDocument("UTF-8", "1.0");
            start(xml, "ENVELOPE");
            start(xml, "HEADER");
            text(xml, "TALLYREQUEST", "Import Data");
            xml.writeEndElement();
            start(xml, "BODY");
            start(xml, "IMPORTDATA");
            start(xml, "REQUESTDESC");
            text(xml, "REPORTNAME", "Vouchers");
            xml.writeEndElement();
            start(xml, "REQUESTDATA");
            start(xml, "TALLYMESSAGE");
            xml.writeNamespace("UDF", "TallyUDF");
            xml.writeStartElement("VOUCHER");
            xml.writeAttribute("VCHTYPE", "Attendance");
            xml.writeAttribute("ACTION", "Create");
            text(xml, "DATE", month.atEndOfMonth().format(TALLY_DATE));
            text(xml, "VOUCHERTYPENAME", "Attendance");
            for (MusterRow row : rows) {
                String name = map.get(row.worker().id());
                if (name == null) {
                    unmapped++;
                    continue;
                }
                employees++;
                entry(xml, name, "Present Days", Integer.toString(row.present()));
                entry(xml, name, "Absent Days", Integer.toString(row.absent()));
                entry(xml, name, "Overtime Hours", String.format(java.util.Locale.ROOT, "%.1f", row.overtimeHours()));
            }
            xml.writeEndElement(); // VOUCHER
            xml.writeEndElement(); // TALLYMESSAGE
            xml.writeEndElement(); // REQUESTDATA
            xml.writeEndElement(); // IMPORTDATA
            xml.writeEndElement(); // BODY
            xml.writeEndElement(); // ENVELOPE
            xml.writeEndDocument();
            xml.close();
        } catch (XMLStreamException e) {
            throw new IllegalStateException("could not build the Tally file", e);
        }
        try {
            out.flush();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        return new TallyFile(out.toByteArray(), employees, unmapped);
    }

    private static void entry(XMLStreamWriter xml, String employee, String type, String value) throws XMLStreamException {
        start(xml, "ATTENDANCEENTRIES.LIST");
        text(xml, "EMPLOYEENAME", employee);
        text(xml, "ATTENDANCETYPE", type);
        text(xml, "ATTDTYPEVALUE", value);
        xml.writeEndElement();
    }

    private static void start(XMLStreamWriter xml, String name) throws XMLStreamException {
        xml.writeStartElement(name);
    }

    /** Text goes through the XML writer, so &amp; &lt; &gt; and quotes in names are escaped. */
    private static void text(XMLStreamWriter xml, String name, String value) throws XMLStreamException {
        xml.writeStartElement(name);
        xml.writeCharacters(value);
        xml.writeEndElement();
    }

    static String asString(byte[] bytes) {
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
