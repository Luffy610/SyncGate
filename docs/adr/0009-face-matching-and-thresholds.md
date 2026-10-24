# ADR-0009: Exact 1:N cosine matching with margin and multi-frame agreement

- **Status:** Accepted (threshold values calibrated per model version)
- **Date:** 24-10-2026
- **Deciders:** ML, Engineering
- **Related:** FR-ATT-01, FR-ATT-03, FR-ATT-06 · NFR-ACC-01, NFR-ACC-04, NFR-ACC-07 · §3.3 metrics · ADR-0006, ADR-0008

## Context

The PRD targets **FAR ≤0.1%** and **FRR ≤2%** (first attempt, normal light), with ≤5% in adverse conditions. In a 1:N search the chance of a false accept grows with N: roughly, system FAR ≈ N × per-comparison FAR. With ≤25 workers × ≤6 templates, N is tiny. That lets us be **strict** while staying fast.

## Decision

### 1. Search

- **Exact brute-force** cosine similarity over all active templates. That is ≤150 dot products of 512-d float vectors (<1 ms). No approximate index (HNSW, etc.) is needed or wanted.
- Score per worker = **max** over that worker's slots.

### 2. Acceptance rule

A match for worker *W* is accepted only when **all** hold:

1. `top1_score(W) ≥ T_match`. Calibrated so that **system** FAR at N = 25 is ≤0.1%, i.e. a per-comparison FAR of about 0.004%.
2. `top1_score − top2_score (different worker) ≥ M_margin` (start at 0.08). This rejects look-alikes.
3. The **same W wins in ≥2 of the last 3 analysed frames** within 1 s (multi-frame agreement).
4. Liveness accepted ([ADR-0007](0007-liveness-detection.md)).

If 1 passes but 2 or 3 fail, the UI keeps scanning for up to 2 s ("Hold still…") before showing "Not recognised".

### 3. Masked faces

If the detector flags a likely mask (lower-face occlusion score) and the worker has a mask slot, the mask slot is compared with its own calibrated `T_match_mask`. Margin and agreement rules still apply. Target: FRR ≤5% with masks, FAR unchanged (NFR-ACC-04).

### 4. Configurability

Owners do **not** see raw thresholds. Settings offer **Strict / Standard / Relaxed** presets. They move `T_match` within vendor-defined safe bounds (PRD §8.3) that never allow system FAR above 0.1% in our evaluation. The default is **Standard**.

### 5. Fairness (NFR-ACC-07)

Thresholds are fixed **globally**, not per person. Calibration and validation run per demographic slice (skin tone, gender, age band). No slice's FRR may exceed **1.5×** the overall FRR. If one does, the model is not released.

## Options considered

| Option | Verdict |
|---|---|
| Single-frame decision | Rejected: more false accepts from motion blur. |
| Approximate nearest-neighbour index | Unnecessary at this N. |
| Per-worker adaptive thresholds | Rejected: hard to audit and a fairness risk. |
| 1:1 verification (worker types an ID first) | Rejected: needs a touch, which breaks hands-free (NFR-UX-01). Kept only inside the guard fallback. |

## Consequences

- Each model release carries a **threshold table** (`T_match`, `T_match_mask`, `M_margin`, `T_adapt`, `T_dup`) in its model card, versioned with the model.
- The exceptions report can filter "low-margin matches" for owner review (FR-RPT-06).
