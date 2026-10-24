# ADR-0001: Phase 1 scope — one phone, one gate, up to 25 workers, fully offline

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Product, Engineering, Design, Sales
- **Related:** PRD §1, §3, §5.1, §6.1, §7.1, §7.3, §12 · supersedes the device and headcount assumptions in PRD v0.2

## Context

PRD v0.2 scoped v1 as *one factory, one device, one gate, fully offline*, with the device being an **8–10" tablet** and a target customer of **50–200 workers**. That implied a throughput target of **200 workers in ≤10 minutes** (≥20 workers/min). It also meant gate UX tuned for reading at 1.5 m on a tablet stand.

Further discovery with the launch clusters has narrowed the first customer:

- The first paying owners run **very small units (typically 8–25 workers)**: job-work stitching, small hosiery units, small machine shops.
- Most already own a spare or cheap **Android phone**. Buying a tablet and a stand is a purchase decision they delay.
- With ≤25 workers there is **no real gate queue**. The shift-change rush is a handful of people over a few minutes.
- The owner is usually the only admin and wants to do everything — attendance, enrolment, corrections, export — **on the same device**.

## Decision

Phase 1 ships for this exact profile:

| Dimension | Phase 1 decision |
|---|---|
| Device | **One phone** (Android or iOS), used in portrait. Tablets still work through the same responsive layouts, but they are not the design target. |
| Roles of the device | **Gate kiosk + enrolment station + admin console** on the same phone (see [ADR-0004](0004-single-device-gate-and-admin-modes.md)). |
| Workforce | **Up to 25 active workers** per factory. All UX, performance budgets and copy assume this. |
| Gates / sites | One gate, one site. |
| Connectivity | Fully offline. Internet is used only for licence check-in and optional backup. |
| Platforms | Android **and** iOS, with all P0 features on both (FR-PLT-01). |
| Distribution | Direct to small factory owners (PRD §5.3). |

### Restated targets (replacing PRD numbers that assumed tablets or 200 workers)

| PRD item | PRD v0.2 | Phase 1 |
|---|---|---|
| Throughput (NFR-PERF-01) | 200 workers ≤10 min, ≥20/min | **25 workers ≤3 min**; ≤3 s walk-up → confirmation per worker remains |
| Pipeline latency (NFR-PERF-02) | ≤700 ms p95 with 500 enrolled | **≤700 ms p95 with 25 enrolled** on the reference phone |
| Template capacity (NFR-PERF-03) | 1,000 templates | **25 workers × up to 6 templates = 150 vectors**; tested to 50 workers for headroom |
| Monthly export (NFR-PERF-05) | 200 workers ≤15 s | 25 workers **≤3 s** |
| Readability (NFR-UX-04) | Readable from 1.5 m | Readable from **0.6–1 m** (a phone on a stand at arm's length) |
| Hardware (NFR-HW-01) | ₹8–10k tablet, 3–4 GB RAM | **Budget phone**, see [ADR-0019](0019-supported-devices-and-os-versions.md) |
| Storage (NFR-HW-03) | 1 year × 200 workers ≤100 MB | 1 year × 25 workers ≤**20 MB** of data; install ≤80 MB |
| Continuous run (NFR-HW-04) | 12 h mains, 4 h battery | 12 h on charger; **≥4 h on battery in gate mode** with duty cycling ([ADR-0018](0018-power-thermal-and-reliability-on-a-phone.md)) |
| Setup time (NFR-UX-02) | ≤30 min | ≤30 min including enrolling the first 5 workers |
| Enrolment (NFR-UX-03) | ≤60 s per worker | ≤60 s per worker |

Everything else in PRD §6 (FR-*) and §9 (CMP-*) stays in force unless an ADR says otherwise.

## Options considered

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Phone, ≤25 workers (chosen)** | No hardware purchase; matches the first customers; simplest UX; tiny 1:N gallery helps accuracy | Smaller screen; phone also used for other things unless locked; battery and heat under continuous camera use | **Chosen** |
| B. Tablet, 50–200 workers (PRD v0.2) | Bigger screen; matches larger units | Extra purchase; throughput risk R-1 on budget hardware; customers not ready | Deferred to Phase 2 |
| C. Phone at gate + second phone for admin | Separates concerns | Needs sync (explicit non-goal), two licences, templates on two devices | Rejected for Phase 1 |

## Consequences

**Positive**
- Throughput risk R-1 mostly goes away. 25 workers at ~3 s each is ~75 s of pure processing.
- A small gallery (≤150 vectors) lets us use stricter thresholds and multi-frame agreement without hurting speed ([ADR-0009](0009-face-matching-and-thresholds.md)).
- The guard fallback can be a **pick-from-list** of the workers not yet marked, not a keypad ([ADR-0004](0004-single-device-gate-and-admin-modes.md)).
- No tablet stand is required. A ₹200–400 phone stand plus a charger is enough.

**Negative / risks**
- The phone is a single point of failure, even more than a tablet (it is also more likely to be borrowed). Mitigated by kiosk locking, backups and the paper fallback ([ADR-0013](0013-backup-restore-and-device-replacement.md), [ADR-0018](0018-power-thermal-and-reliability-on-a-phone.md)).
- Continuous camera use on a phone raises battery and heat concerns ([ADR-0018](0018-power-thermal-and-reliability-on-a-phone.md)).
- Factories that grow past 25 workers need a path to Phase 2. We will **warn, not block**, at 25 active workers until pricing (D-3) decides whether 25 is a hard licence limit.

## Follow-ups

- Update PRD to v0.3 with this scope and the restated targets.
- D-3: decide whether the 25-worker figure is a licence tier.
- Sales qualification script: confirm headcount ≤25 and one gate before the trial starts.
