package in.syncgate.api.report;

import in.syncgate.api.attendance.ExceptionService;
import in.syncgate.api.audit.AuditService;
import in.syncgate.api.common.AppClock;
import in.syncgate.api.common.ChainService;
import in.syncgate.api.common.Db;
import in.syncgate.api.common.Uuid7;
import in.syncgate.api.domain.Enums.ExportFormat;
import in.syncgate.api.domain.Wire;
import in.syncgate.api.report.ReportService.MusterRow;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.YearMonth;
import java.time.format.DateTimeFormatter;
import java.util.HexFormat;
import java.util.List;
import org.apache.poi.ss.usermodel.Cell;
import org.apache.poi.ss.usermodel.CellStyle;
import org.apache.poi.ss.usermodel.DataFormat;
import org.apache.poi.ss.usermodel.Font;
import org.apache.poi.ss.usermodel.Row;
import org.apache.poi.ss.usermodel.Sheet;
import org.apache.poi.xssf.usermodel.XSSFWorkbook;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Payroll exports (ADR-0015, amended: Excel and CSV; Tally XML is dropped).
 * Each export is logged with its SHA-256 and the audit-chain head, and the
 * file content itself is never kept. Export is never blocked by licence state.
 */
@Service
public class ExportService {

    public static final String XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    public static final String CSV = "text/csv; charset=utf-8";
    private static final DateTimeFormatter DMY = DateTimeFormatter.ofPattern("dd-MM-yyyy");

    public static final String XML = "application/xml; charset=utf-8";

    /** {@code unmapped} is only used by Tally files: workers left out for lack of a Tally name. */
    public record ExportFile(String fileName, String contentType, byte[] bytes, int rows, String sha256,
            int unmapped) {}

    private final ReportService reports;
    private final in.syncgate.api.tally.TallyService tally;
    private final ExceptionService exceptions;
    private final AuditService audit;
    private final ChainService chain;
    private final JdbcClient jdbc;
    private final AppClock clock;

    public ExportService(ReportService reports, in.syncgate.api.tally.TallyService tally,
            ExceptionService exceptions, AuditService audit, ChainService chain,
            JdbcClient jdbc, AppClock clock) {
        this.reports = reports;
        this.tally = tally;
        this.exceptions = exceptions;
        this.audit = audit;
        this.chain = chain;
        this.jdbc = jdbc;
        this.clock = clock;
    }

    @Transactional
    public ExportFile export(ExportFormat format, ReportService.Filter filter, String actor) {
        List<MusterRow> rows = reports.monthly(filter);
        YearMonth month = filter.month();
        byte[] bytes;
        String ext;
        String type;
        int count = rows.size();
        int unmapped = 0;
        switch (format) {
            case CSV -> {
                bytes = csv(rows, month);
                ext = "csv";
                type = CSV;
            }
            case TALLY -> {
                var file = tally.build(rows, month);
                bytes = file.bytes();
                ext = "xml";
                type = XML;
                count = file.employees();
                unmapped = file.unmapped();
            }
            default -> {
                bytes = xlsx(rows, month);
                ext = "xlsx";
                type = XLSX;
            }
        }
        String name = "SyncGate_" + (format == ExportFormat.TALLY ? "Tally" : "Muster") + "_" + month + "." + ext;
        String sha = sha256(bytes);
        jdbc.sql("INSERT INTO exports (id, created_at, format, period, sha256, row_count, created_by) "
                        + "VALUES (:id, :at, :f, :p, :sha, :n, :by)")
                .param("id", Uuid7.next()).param("at", Db.ts(clock.now())).param("f", Wire.of(format))
                .param("p", month.toString()).param("sha", sha).param("n", count).param("by", actor).update();
        audit.record(actor, "export.created", Wire.of(format) + " " + month + " " + count + " rows"
                + (unmapped > 0 ? ", " + unmapped + " not mapped" : ""));
        return new ExportFile(name, type, bytes, count, sha, unmapped);
    }

    // ---- CSV ---------------------------------------------------------------

    static byte[] csv(List<MusterRow> rows, YearMonth month) {
        StringBuilder out = new StringBuilder("﻿"); // BOM so Excel opens UTF-8 (Hindi names) correctly
        out.append(line(header(month)));
        for (MusterRow row : rows) {
            out.append(line(cells(row)));
        }
        return out.toString().getBytes(StandardCharsets.UTF_8);
    }

    static List<String> header(YearMonth month) {
        List<String> head = new java.util.ArrayList<>(List.of("Worker ID", "Name", "Department", "Contractor",
                "Present", "Absent", "Late", "Overtime hours", "Needs review"));
        for (int d = 1; d <= month.lengthOfMonth(); d++) {
            head.add(month.atDay(d).format(DMY));
        }
        return head;
    }

    static List<String> cells(MusterRow row) {
        List<String> cells = new java.util.ArrayList<>(List.of(row.worker().code(), row.worker().name(),
                row.worker().department(), row.worker().contractor() == null ? "" : row.worker().contractor(),
                Integer.toString(row.present()), Integer.toString(row.absent()), Integer.toString(row.late()),
                String.format(java.util.Locale.ROOT, "%.1f", row.overtimeHours()),
                row.hasOpenExceptions() ? "YES" : ""));
        cells.addAll(row.days());
        return cells;
    }

    private static String line(List<String> cells) {
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < cells.size(); i++) {
            if (i > 0) {
                out.append(',');
            }
            out.append(csvCell(cells.get(i)));
        }
        return out.append("\r\n").toString();
    }

    /**
     * Quotes per RFC 4180 and defuses spreadsheet formulas: a cell starting
     * with = + - @ (or tab/CR) is prefixed with an apostrophe so Excel treats
     * it as text. Worker names are user input, so this matters.
     */
    static String csvCell(String value) {
        String text = value == null ? "" : value;
        if (!text.isEmpty() && "=+-@\t\r".indexOf(text.charAt(0)) >= 0) {
            text = "'" + text;
        }
        if (text.contains(",") || text.contains("\"") || text.contains("\n") || text.contains("\r")) {
            return "\"" + text.replace("\"", "\"\"") + "\"";
        }
        return text;
    }

    // ---- Excel -------------------------------------------------------------

    byte[] xlsx(List<MusterRow> rows, YearMonth month) {
        try (XSSFWorkbook book = new XSSFWorkbook(); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            Font bold = book.createFont();
            bold.setBold(true);
            CellStyle head = book.createCellStyle();
            head.setFont(bold);
            DataFormat formats = book.createDataFormat();
            CellStyle hours = book.createCellStyle();
            hours.setDataFormat(formats.getFormat("0.0"));

            Sheet muster = book.createSheet("Muster");
            writeRow(muster.createRow(0), header(month), head, null);
            int r = 1;
            for (MusterRow row : rows) {
                Row sheetRow = muster.createRow(r++);
                List<String> text = cells(row);
                for (int c = 0; c < text.size(); c++) {
                    Cell cell = sheetRow.createCell(c);
                    // Counts and hours are real numbers; everything else is text, never a formula.
                    if (c >= 4 && c <= 7) {
                        cell.setCellValue(Double.parseDouble(text.get(c)));
                        if (c == 7) {
                            cell.setCellStyle(hours);
                        }
                    } else {
                        cell.setCellValue(text.get(c));
                    }
                }
            }
            muster.createFreezePane(2, 1);
            for (int c = 0; c < 9; c++) {
                muster.autoSizeColumn(c);
            }

            Sheet summary = book.createSheet("Summary");
            writeRow(summary.createRow(0), List.of("Worker ID", "Name", "Present", "Absent", "Late", "Overtime hours"),
                    head, null);
            int s = 1;
            for (MusterRow row : rows) {
                Row sheetRow = summary.createRow(s++);
                sheetRow.createCell(0).setCellValue(row.worker().code());
                sheetRow.createCell(1).setCellValue(row.worker().name());
                sheetRow.createCell(2).setCellValue(row.present());
                sheetRow.createCell(3).setCellValue(row.absent());
                sheetRow.createCell(4).setCellValue(row.late());
                Cell ot = sheetRow.createCell(5);
                ot.setCellValue(row.overtimeHours());
                ot.setCellStyle(hours);
            }

            Sheet review = book.createSheet("Exceptions");
            writeRow(review.createRow(0), List.of("Kind", "Date", "Worker ID", "Actor"), head, null);
            int e = 1;
            for (var ex : exceptions.all()) {
                if (ex.resolved()) {
                    continue;
                }
                Row sheetRow = review.createRow(e++);
                sheetRow.createCell(0).setCellValue(Wire.of(ex.kind()));
                sheetRow.createCell(1).setCellValue(ex.at().atZone(clock.zone()).toLocalDate().format(DMY));
                sheetRow.createCell(2).setCellValue(ex.workerId() == null ? "" : ex.workerId().toString());
                sheetRow.createCell(3).setCellValue(ex.actor() == null ? "" : ex.actor());
            }

            Sheet about = book.createSheet("About");
            String[][] meta = {
                {"Period", month.toString()},
                {"Generated", LocalDate.now(clock.zone()).format(DMY)},
                {"Workers", Integer.toString(rows.size())},
                {"Audit chain head", String.valueOf(chain.head(AuditService.CHAIN))},
                {"Attendance chain head", String.valueOf(chain.head("attendance"))},
            };
            for (int i = 0; i < meta.length; i++) {
                Row sheetRow = about.createRow(i);
                sheetRow.createCell(0).setCellValue(meta[i][0]);
                sheetRow.createCell(1).setCellValue(meta[i][1]);
            }
            book.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    }

    private static void writeRow(Row row, List<String> values, CellStyle style, CellStyle unused) {
        for (int c = 0; c < values.size(); c++) {
            Cell cell = row.createCell(c);
            cell.setCellValue(values.get(c));
            cell.setCellStyle(style);
        }
    }

    static String sha256(byte[] bytes) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }
}
