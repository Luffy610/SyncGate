# ADR-0008: Guided multi-angle enrolment; several templates per worker; no raw images kept

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** ML, Product, Design, Legal
- **Related:** FR-ENR-01..07 · FR-DPR-01..04 · CMP-01, CMP-02, CMP-04, CMP-05, CMP-10 · NFR-SEC-02 · NFR-UX-03 · Designs 12–14

## Context

Recognition quality is decided mostly at enrolment. Enrolment is also where the **privacy notice and consent** (CMP-01, CMP-02, FR-ENR-02) and the **under-18 block** (CMP-10) happen. The owner enrols workers personally on the gate phone. It must take **≤60 s per worker** (NFR-UX-03).

## Decision

### 1. Three-step flow (designs 12 → 13 → 14)

| Step | Content | Rules |
|---|---|---|
| **1. Details** | Full name, worker ID (auto `W-0101…`, editable, unique), date of birth, department, designation, shift group, contractor (optional), phone (optional), worker's language | **DOB → age < 18 blocks enrolment** and alerts the owner (CMP-10). The ID must be unique. Name is required. |
| **2. Notice & consent** | Notice in the worker's language: what is collected, why, where it is kept, rights, grievance contact. A **"Read aloud"** button plays it ([ADR-0016](0016-localization-voice-and-indian-formats.md)). The worker taps the agree box. | Saved as a **consent record**: worker ID, notice version + language, legal basis (consent / legitimate use — TBD-L1, configurable), timestamp, enrolling admin. You cannot skip to step 3 without it. |
| **3. Face capture** | Auto-capture of **Front → Left → Right**, plus an optional **Mask** sample. Live guidance ring and quality hints. | Each angle needs ≥3 good frames. Poor captures are rejected with a reason (FR-ENR-04): too dark, blurry, face covered, too far, turn less. |

### 2. What is stored

| Item | Stored? | Where |
|---|---|---|
| Raw camera frames | **Never written.** Held only in native memory during capture, zeroed after embedding. | — |
| Aligned crops | **Never written.** | — |
| Embeddings | **Yes**: up to **6 per worker** (front ×2, left, right, mask, plus one adaptive slot — see below) | Native **TemplateVault**, encrypted, non-exportable ([ADR-0010](0010-local-storage-and-encryption.md)) |
| Template metadata | `worker_id`, `slot`, `model_id`, `model_version`, `quality_score`, `created_at` | Encrypted DB |
| Consent record | Yes | Encrypted DB, included in backups |

Templates are **non-reversible, model-specific vectors** (NFR-SEC-02). They are not photos and cannot be turned back into one with practical effort.

### 3. Duplicate detection (FR-ENR-05)

Before saving, the new embeddings are matched against **all** existing templates. If any score passes the duplicate threshold (stricter than the gate threshold), enrolment pauses with "This face looks like **Ramesh Kumar (W-0112)**". The owner can cancel, or override with a reason (twins, etc.). Overrides are audit-logged.

### 4. Adaptive template (controlled)

One extra slot per worker may be **refreshed automatically** with a high-confidence gate capture (score ≥ `T_adapt`, liveness ≥ `T_live_high`, quality ≥ 0.8). It is refreshed at most once per 14 days. This tracks gradual change (beard, weight, ageing). Enrolment slots are never overwritten automatically. Adaptive updates are logged as an audit event (without vectors).

### 5. Re-enrolment, deactivation and erasure (FR-ENR-07, FR-DPR-02, FR-DPR-03)

| Action | Effect |
|---|---|
| Re-enrol | Replaces all slots for the worker. The old templates are securely deleted. |
| Deactivate | The worker stops matching at the gate. Templates are kept for a configurable period (default **90 days**), then **auto-deleted** (FR-DPR-03). |
| Delete worker | Templates are erased immediately. Worker details are erased, or kept as a **wage-record stub** (ID, name, attendance) for the legal retention period (TBD-L3). The erasure itself is audit-logged. |
| Restore on a new phone | Worker details restore; templates do not ([ADR-0013](0013-backup-restore-and-device-replacement.md)). Workers show "Needs face" and re-enrol in about 30 s each. |

## Options considered

| Option | Verdict |
|---|---|
| Single frontal template | Rejected: weak on pose and masks. |
| Keep a reference photo for re-training / disputes | Rejected: contradicts CMP-04 and the sales message. |
| Fully automatic template updating | Rejected: template-poisoning risk (a look-alike slowly takes over). Limited to one capped slot. |
| Bulk enrolment by CSV + faces later | P1 (FR-ENR-06). With ≤25 workers it is not urgent. |

## Consequences

- Enrolment is **≤60 s** in testing with a cooperative worker. The consent screen is the main time cost and is intentional.
- When the embedding model changes, every worker must re-enrol ([ADR-0006](0006-on-device-vision-pipeline.md) §6).
