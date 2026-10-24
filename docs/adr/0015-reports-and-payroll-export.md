# ADR-0015: On-device reports; Excel (.xlsx) and Tally Prime XML exports through the OS share sheet

- **Status:** Accepted (Tally Prime only for Phase 1 — confirms D-5 unless sales evidence says otherwise before M2)
- **Date:** 24-10-2026
- **Deciders:** Product, Engineering
- **Related:** FR-RPT-01..06 · TC-06 · NFR-PERF-05 · §3.3 "Tally accepts without manual edits ≥95%" · Designs 10, 15, 16 · ADR-0011, ADR-0012

## Context

The owner (or a part-time accountant) runs payroll in **Excel** and/or **Tally**. Exports must be correct with no manual edits. They must also work offline and be easy to send through WhatsApp, which is how files actually move in these businesses.

## Decision

### 1. Reports (on device)

| Report | Content | Filters |
|---|---|---|
| **Today** (design 10) | Present / absent / late / on premises, exceptions count, backup state | Shift |
| **Daily** | Per worker: IN, OUT, worked hours, status, flags | Date, department, shift |
| **Monthly muster roll** (design 16) | Per worker per day: P / A / HD / L(ate) / WO / flags; totals P, A, Late, OT h | Month, department, shift, contractor |
| **Exceptions** (design 15) | Manual entries, missing OUT, low-margin matches, liveness-active accepts, duplicate-enrol overrides, clock changes, spoof suspicions | Kind, status, date |
| **Worker summary** (FR-DPR-01) | Personal data summary for a worker request | Worker |

All reports are computed by the shift engine on demand ([ADR-0012](0012-time-shifts-and-attendance-rules-engine.md)). Each export first checks for **open exceptions** and warns ("2 records still need review — they'll be marked ⚑").

### 2. Excel (.xlsx)

- Generated with the **`excel`** Dart package (MIT) in a background isolate.
- **Column templates** are JSON definitions, with a default "Payroll" template (design 16). Owners can reorder columns, hide them and rename headers.
- Sheets: `Muster` (grid), `Summary` (totals per worker), `Exceptions`, `About` (factory, period, generated at, app version, rule versions, audit-chain head hash).
- Formats: dates as real Excel dates displayed **DD-MM-YYYY**; hours as decimal hours (e.g. 8.5) **and** `[h]:mm`; Indian digit grouping for numbers ≥1,000 (FR-L10N-05).
- File name: `SyncGate_<Factory>_Muster_2026-10.xlsx` (ASCII-safe, with a transliterated factory name).

### 3. Tally Prime XML (FR-RPT-04, TC-06)

- **Target:** Tally Prime (current release line). Tally ERP 9 is out of scope for Phase 1 (D-5).
- Output: an XML **import file** with `ENVELOPE › HEADER (TALLYREQUEST=Import Data) › BODY › IMPORTDATA › REQUESTDESC (REPORTNAME=Vouchers) › REQUESTDATA › TALLYMESSAGE › VOUCHER (VCHTYPE="Attendance")`. It contains one `ATTENDANCEENTRIES.LIST` per employee with the configured **attendance/production types** (e.g. "Present Days", "Overtime Hours", "Absent Days").
- **Employee mapping:** a mapping table links `worker_code` → Tally **employee master name**. It is set once in Settings › Tally. Unmapped workers block Tally export with a fix-it list (design 16: "23 of 24 matched · 1 to map").
- Attendance-type names are configurable to match the customer's Tally company.
- The file is **only written**. We never talk to Tally's HTTP/ODBC server (TC-06). The accountant imports via *Import › Transactions*.
- A **compatibility test suite** imports generated files into a real Tally Prime instance in CI-adjacent manual QA before each release (target: ≥95% of exports import with no edits).

### 4. Sharing (FR-RPT-05)

- `share_plus` → OS share sheet (WhatsApp, email, Drive, Files, USB). Also "Save to device" (Android `MediaStore.Downloads` / iOS Files).
- Each export writes an `exports` row with the file **SHA-256**, period, template and user ([ADR-0011](0011-data-model-append-only-events.md)). The file content is not kept.
- Exports go through the audit log (FR-ADM-03) and are blocked for the Gate-operator role (FR-ADM-01).
- Export is **never blocked by licence state** (FR-LIC-04).

## Options considered

| Option | Verdict |
|---|---|
| CSV only | Rejected: owners expect formatted Excel; CSV dates break in Excel with Indian locales. |
| Syncfusion XlsIO | Capable, but a commercial licence is needed above revenue thresholds; `excel` is enough. |
| Tally via ODBC/HTTP (port 9000) | Rejected (TC-06): needs Tally running on the same network; fragile. |
| PDF muster roll | Nice-to-have; the printable worker summary covers the legal need in Phase 1. |

## Consequences

- We need a Tally Prime licence for QA and a small library of real customer Tally setups to test against.
- Statutory register formats (FR-RPT-07) remain P2.
