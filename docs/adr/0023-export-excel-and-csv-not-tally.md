# ADR-0023: Payroll export is Excel and CSV; Tally XML is dropped from Phase 1

- **Status:** In review
- **Proposed outcome:** Accepted (supersedes the Tally part of ADR-0015)
- **Date:** 28-10-2026
- **Deciders:** Product, Engineering
- **Related:** PRD FR-RPT-03, FR-RPT-04, FR-RPT-05 · TC-06 · ADR-0015 · D-5

## Context

[ADR-0015](0015-reports-and-payroll-export.md) chose Excel (.xlsx) and Tally Prime XML, and rejected CSV-only because
Excel mangles dates and non-ASCII text in CSV. Since then the product owner asked for **CSV and Excel**
and the Tally path has the heaviest cost: a Tally Prime licence, real-Tally import QA, an employee-mapping screen
and a mapping table (decision D-5 was still open).

## Decision

- Phase 1 exports **Excel (.xlsx)** and **CSV (.csv)** only. Both come from the same muster data, computed by the
  server from the append-only events.
- **Tally Prime XML, the employee-mapping screen and the mapping table are removed** from Phase 1. They can come
  back as their own ADR once there is a customer who needs them.
- CSV is written so that Excel opens it correctly, which addresses the objection in ADR-0015:
  - UTF-8 **with a byte-order mark**, so Hindi and other Indian-script names display correctly;
  - RFC 4180 quoting, CRLF line endings;
  - dates as **DD-MM-YYYY** text in the header, counts as plain numbers;
  - **formula injection is defused**: any cell starting with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'`,
    because worker names are user input.
- Excel keeps the sheets from ADR-0015: `Muster`, `Summary`, `Exceptions`, `About` (period, generated date and
  the audit-chain head hashes). Cells are real text or numbers, never formulas.
- Every export writes an `exports` row (format, period, SHA-256, row count, user) and an audit entry. The file
  content is not kept. Export is never blocked by licence state (FR-LIC-04) and is refused for the Gate-operator role.

## Consequences

- PRD FR-RPT-04 (Tally) and decision D-5 are parked, not met, in Phase 1.
- The `tally_*` strings, `TallyScreen` and `TallyMappingRepository` are deleted from the app.
- The accountant must key or paste totals into Tally themselves until a Tally path exists.
