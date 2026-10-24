# ADR-0012: Pure-Dart shift and rules engine; time model and clock-integrity checks

- **Status:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, Product
- **Related:** FR-ATT-04, FR-ATT-05, FR-SHF-01..07, FR-OFF-06, FR-L10N-05 · ADR-0011, ADR-0015

## Context

Payroll correctness is the second promise of the product, after fraud prevention. The PRD requires:

- night shifts crossing midnight,
- grace, late mark, early exit, half day, minimum hours, break deduction, overtime,
- missing-punch handling,
- clock-tamper detection.

All of this offline, with the phone's clock as the only clock most of the time.

## Decision

### 1. Engine shape

- `ShiftEngine` lives in `sg_domain` as **pure, deterministic Dart**: `(events, corrections, rules, calendar) → List<DayRecord>`. It does no I/O and never reads the clock itself.
- It runs on demand (Today screen, reports, exports) and is cheap at ≤25 workers.
- It is covered by a **golden test suite** of real-world scenarios (see §5). Every rule change needs a new golden case.

### 2. Time model

| Field | Meaning |
|---|---|
| `ts_utc` | Wall-clock instant at capture (UTC) |
| `ts_local_offset` | Offset at capture (normally +05:30) |
| `mono_ns` + `boot_id` | Monotonic time since boot (`SystemClock.elapsedRealtimeNanos` / `clock_gettime(CLOCK_MONOTONIC_RAW)` via `mach_continuous_time`) and a boot identifier |
| `attribution_date` | The **shift date** an event belongs to (derived, not stored) |

- All calculations use the **factory timezone** (`Asia/Kolkata`, no DST), via the `timezone` package with a bundled tzdb.
- Displayed formats follow Indian conventions: **DD-MM-YYYY**, 12/24-hour toggle (FR-L10N-05).

### 3. Direction and attribution

- **Direction (FR-ATT-04):** if the worker's last valid event in the current attribution window is IN → next is OUT, otherwise IN. Edge rule: an OUT more than *X* hours (default 16) after the last IN starts a new IN, and the old IN is flagged as a missing OUT.
- **Night shifts:** a shift `22:00–06:00` is attributed to the **start date**. Events from `start − early_window` (default 2 h) to `end + late_window` (default 4 h) belong to that shift instance.
- **Cooldown (FR-ATT-05):** a second face match for the same worker within **2 minutes** is ignored (configurable 1–10 min).

### 4. Rules (per shift group, versioned by `effective_from`)

| Rule | Default |
|---|---|
| Grace period | 10 min |
| Late mark after | start + grace |
| Early exit before | end − 10 min |
| Half day if worked | < 4 h 30 m |
| Full day minimum | 7 h 30 m |
| Break deduction | Fixed 30 min, or none |
| Overtime | Daily: worked − (shift length − breaks) beyond 30 min, rounded down to 30 min; weekly threshold optional; multiplier labels (1.5×, 2×) exported, never computed as money |
| Missing OUT (FR-SHF-06) | Auto-close at shift end + 4 h **flagged**, counts as present for the shift minimum, raises an exception |
| Weekly off | Sunday (configurable) |

Holiday calendars, leave and rotating shifts are **P1** (FR-SHF-04/05) and come after GA.

### 5. Golden scenarios (examples)

| # | Scenario | Expected |
|---|---|---|
| G1 | Day shift 06:00–14:00, IN 06:04, OUT 14:02 | Present, on time, 0 OT |
| G2 | IN 06:12 | Late (after 06:10 grace) |
| G3 | Night 22:00–06:00, IN 21:55 (23-10), OUT 06:05 (24-10) | One record dated 23-10, full day |
| G4 | IN 06:00, no OUT | Auto-closed 18:00, flagged, exception |
| G5 | IN 06:00, OUT 10:00 | Half day |
| G6 | IN 06:00, OUT 17:30 | 3 h worked beyond shift → OT 3.0 h |
| G7 | Two face matches 30 s apart | One event |
| G8 | Manual IN + correction retime | Derived record uses the corrected time; both are visible in the audit |
| G9 | Clock moved back 14 min at 02:10 | Events after the jump flagged; exception raised |

### 6. Clock integrity (FR-OFF-06)

- On every event we compare `Δwall` vs `Δmono` against the previous event in the same `boot_id`. A difference beyond **±2 min** → `clock_flag = jump` on the event and a **clock-change exception** (design 15).
- On reboot (new `boot_id`), wall time is compared with the **last trusted time**, the most recent of:
  - (a) the licence server's signed timestamp,
  - (b) the HTTPS `Date` header from the licence server,
  - (c) the OS's network-time status, where exposed (Android `SystemClock.currentNetworkTimeClock()` on API 33+).
  A wall clock earlier than the last trusted time → flag.
- Listen for `ACTION_TIME_CHANGED` / `ACTION_TIMEZONE_CHANGED` (Android) and `NSSystemClockDidChange` (iOS) and record an audit entry.
- Flagged events stay valid but are **marked in exports** for owner review. We never "correct" times silently.

## Options considered

| Option | Verdict |
|---|---|
| Compute and store daily rows at capture time | Rejected: rule changes and corrections would need rewrites (see ADR-0011). |
| Rules as a scripting DSL | Overkill for Phase 1. Typed rule objects are enough. |
| Trust device time only | Rejected: the easiest fraud is changing the phone clock. |

## Consequences

- Changing a shift rule mid-month applies from `effective_from` only. Earlier days keep their old rules.
- Exports are reproducible: the same inputs always produce the same output file (hash recorded in `exports`).
