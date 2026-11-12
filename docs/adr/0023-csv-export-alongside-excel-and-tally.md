# ADR-0023: CSV is added to the payroll export, next to Excel and Tally

- **Status:** In review
- **Proposed outcome:** Accepted (amends ADR-0015; Tally stays)
- **Date:** 28-10-2026
- **Deciders:** Product, Engineering
- **Related:** PRD FR-RPT-03, FR-RPT-04, FR-RPT-05 · TC-06 · ADR-0015 · D-5

## Context

[ADR-0015](0015-reports-and-payroll-export.md) chose Excel (.xlsx) and Tally Prime XML and rejected CSV-only,
because Excel mangles dates and non-ASCII text in CSV. The product owner also wants a **CSV** export, and wants
Tally kept. An earlier draft of this work removed Tally; that was a mistake and has been reverted.

## Decision

- Phase 1 exports **three formats** from the same muster data, all produced by the server
  (`services/api`, package `report` and `tally`): **Excel (.xlsx)**, **CSV (.csv)** and **Tally Prime XML**.
- ADR-0015 stays in force for Excel and Tally, including the employee-mapping screen and mapping table.
- CSV is written so Excel opens it correctly, which answers the objection in ADR-0015:
  - UTF-8 **with a byte-order mark** (Hindi and other Indian-script names display correctly);
  - RFC 4180 quoting and CRLF line endings;
  - dates as **DD-MM-YYYY** in the header, counts as plain numbers;
  - **formula injection is defused**: a cell starting with `=`, `+`, `-`, `@`, tab or CR is prefixed with `'`.
- Tally export deviation from ADR-0015: workers **without a Tally name are left out of the file and counted**
  (response header `X-Unmapped`), instead of blocking the export. This matches the app design, which shows
  "23 of 24 matched · 1 to map" and lets the owner continue. The XML layout follows ADR-0015 but has **not yet
  been import-tested against a real Tally Prime company**; that QA step remains open.
- Every export writes an `exports` row (format, period, SHA-256, row count, user) and an audit entry. File
  content is not kept. Export is never blocked by licence state and is refused for the Gate-operator role.

## Consequences

- The Flutter `ExportFormat` is `excel | csv | tally`; the export section shows three options.
- Tally mappings are stored on the server (`tally_mappings`), included in backups, and deleted when a worker is erased.
