# ADR-0011: Append-only attendance events, corrections as new records, hash-chained audit log, UUIDv7 IDs

- **Status:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, Product
- **Related:** FR-ATT-07, FR-SHF-06, FR-SHF-07, FR-ADM-03, FR-DPR-01..03 · TC-05 · CMP-05 · ADR-0010, ADR-0012

## Context

Attendance becomes **wages**. Disputes between owner and worker must be settled from records nobody can quietly change. Phase 2 will add **multi-device sync** without a migration (TC-05). The PRD requires corrections with a reason and a before/after audit (FR-SHF-07), plus a tamper-evident audit log (FR-ADM-03).

## Decision

### 1. Principles

- **Facts are immutable.** An attendance event is never updated or deleted in normal operation.
- **Corrections are new facts** that reference the event they amend.
- **Daily attendance is derived**, recomputed by the shift engine from events + corrections + rules ([ADR-0012](0012-time-shifts-and-attendance-rules-engine.md)).
- **IDs are UUIDv7**: time-ordered, globally unique, generated offline, and ready for merging across devices in Phase 2.
- Each row carries `device_id` (random per install) and a `hlc` (hybrid logical clock) column, unused in Phase 1, so sync can be added without schema changes.

### 2. Core tables (Drift)

| Table | Key columns | Notes |
|---|---|---|
| `factory` | id, name, timezone (`Asia/Kolkata`), locale, created_at | One row |
| `users` | id, name, role (owner/admin/gate_operator), pin_hash, biometric_enabled, active | Admin users, not workers |
| `workers` | id (UUIDv7), worker_code (`W-0101`), full_name, dob, department_id, designation, shift_group_id, contractor_name?, phone?, language, status (active/inactive/erased_stub), created_at, exited_at? | |
| `consents` | id, worker_id, notice_version, notice_language, legal_basis, accepted_at, recorded_by | Append-only; withdrawal = new row |
| `template_meta` | worker_id, slot, model_id, model_version, quality, created_at | Vectors live in the vault |
| `shift_groups`, `shifts`, `rules` | Shift windows, grace, late, early exit, half day, min hours, breaks, OT rules | Versioned: `effective_from` |
| **`attendance_events`** | id, worker_id, device_id, ts_utc, ts_local_offset, mono_ns, boot_id, direction (in/out), method (face/manual/face_active), match_score, margin, liveness_score, reason?, recorded_by?, clock_flag, hlc | **Append-only**. No image fields. |
| `corrections` | id, target_event_id?, worker_id, kind (add/void/retime/redirect), new_ts?, new_direction?, reason (required), corrected_by, created_at | Append-only |
| `exceptions` | id, kind (manual, missing_out, low_margin, clock_change, dup_enrol, spoof_suspect, liveness_active), ref_id, status (open/resolved), resolved_by, resolved_at | Drives design 15 |
| **`audit_log`** | seq, id, ts, actor, action, entity, entity_id, before_json?, after_json?, prev_hash, hash | Append-only, hash-chained |
| `exports`, `backups` | id, kind, period, created_at, created_by, file_hash | Record of what left the device (no content) |
| `licence` | token, device_key_id, last_checkin, state | |

### 3. Tamper evidence

- `audit_log.hash = SHA-256(prev_hash ‖ canonical_json(row_without_hash))`. The first row is chained to a random genesis value.
- `attendance_events` and `corrections` are also chained (each row includes `prev_hash`), so deleting or editing a row breaks the chain.
- SQLite **triggers** reject `UPDATE`/`DELETE` on append-only tables. The only exceptions are the controlled retention purge and worker erasure, and those write an audit entry first.
- Verification runs on each launch (incremental, from the last verified seq) and before every export. A broken chain raises a **"Records may have been tampered with"** exception and is noted in the export file.
- This is *tamper-evident*, not tamper-proof: a rooted attacker with the keys could rebuild the chain. Root detection ([ADR-0017](0017-security-hardening-and-privacy-dpdp.md)) and backups with their own hashes raise the bar.

### 4. Retention and erasure (CMP-05, FR-DPR-02/03, TBD-L3)

| Data | Default retention | Configurable |
|---|---|---|
| Attendance events, corrections | **[TBD-L3 — state wage-record period]**; placeholder default 3 years | Yes, not below the legal minimum |
| Audit log | Same as attendance | — |
| Templates of exited workers | 90 days after `exited_at`, then auto-deleted | 30–180 days |
| Consent records | As long as the attendance they support | — |

Erasure of a worker deletes templates, contact data and DOB. It keeps a **wage-record stub** (worker_code, name, attendance) until the retention period ends, then purges it.

### 5. Worker data summary (FR-DPR-01)

One query assembles worker details, consents, attendance history and corrections into a **PDF/printable summary** in the worker's language. It can be shared through the share sheet. It never contains templates.

## Options considered

| Option | Verdict |
|---|---|
| Mutable "attendance per day" rows | Rejected: corrections overwrite history; disputes become unprovable; sync is harder later. |
| Auto-increment integer IDs | Rejected: collide across devices in Phase 2. |
| UUIDv4 | UUIDv7 chosen for time ordering and index locality. |
| Blockchain / external timestamping | Overkill and needs connectivity. |

## Consequences

- Reports always recompute from facts, which is cheap at ≤25 workers (a month ≈ 1,500 events).
- Schema migrations follow Drift's versioned `MigrationStrategy`, each with a test against a snapshot of the previous schema.
