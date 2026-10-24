# ADR-0007: Passive liveness by default, with an optional active fallback

- **Status:** Proposed — thresholds and fallback behaviour confirmed at M0 and in beta
- **Date:** 24-10-2026
- **Deciders:** ML, Security, Product
- **Related:** FR-ATT-02 · NFR-ACC-08 · Risk R-3 · ADR-0006, ADR-0009

## Context

The whole value of SyncGate is stopping **proxy attendance**. If a worker can hold up a photo or a video of an absent colleague on their own phone, the product fails. The PRD asks for **passive** liveness (no challenge), because active challenges slow the queue. It also asks for an attack acceptance rate of **≤2%** against print, screen-replay and video-replay attacks, tested along the lines of ISO/IEC 30107-3.

With ≤25 workers ([ADR-0001](0001-phase-1-scope-one-phone-25-workers.md)) there is no real queue, so a *short* active step on doubtful cases costs little.

## Decision

### Layered presentation-attack detection (PAD)

| Layer | Signal | Runs |
|---|---|---|
| L1 — Passive texture/frequency | CNN (MiniFASNet class) on 2 crop scales (80×80 at 1.0× and 2.7× context) detecting print texture, moiré and screen bezels | Every candidate frame |
| L2 — Temporal | Over 3–5 consecutive frames: micro-motion of keypoints, natural blink/eyelid variation, consistent 3-D head-pose parallax vs a flat plane | Before a match is accepted |
| L3 — Context | Rectangular bright border or hand-held-device edges around the face (phone-screen attack), sudden exposure jumps typical of screens | Every candidate frame |
| L4 — Active fallback (optional) | "Blink once" / "Turn your head slightly" prompt with voice, shown **only** when L1–L3 are borderline | Only on borderline scores |

### Decision rule

```
live_score = fuse(L1, L2, L3)          # calibrated 0..1
if live_score ≥ T_live_high            → accept (continue to match)
elif live_score ≥ T_live_low and active_fallback_enabled
                                        → run L4 challenge (≤2 s) → accept / reject
else                                    → reject as "Not recognised" (no hint that liveness failed)
```

- **Reject silently**: the UI shows the same "Not recognised" state for a liveness fail and for no match. Attackers learn nothing.
- Every attendance event stores `liveness_score` (FR-ATT-07). Events accepted **via L4** are tagged and appear in the exceptions report filter.
- Active fallback is **on by default** in Phase 1 (small queues). The owner can switch it off in Settings.
- Repeated liveness rejections for the same claimed identity within 10 minutes (≥3) raise an **"Possible spoof attempt"** exception for the owner. No image is stored ([ADR-0017](0017-security-hardening-and-privacy-dpdp.md)).

### Targets

| Metric | Target |
|---|---|
| Attack Presentation Classification Error Rate (APCER) — print, screen, video | ≤2% each species |
| Bona fide rejection (BPCER) at gate | ≤2% (first attempt), ≤0.5% after L4 |
| Added latency (L1–L3) | ≤120 ms p95 |
| L4 challenge duration | ≤2 s |

## Options considered

| Option | Verdict |
|---|---|
| Passive only (PRD) | Kept as the base. Adding an L4 fallback costs almost nothing at ≤25 workers and lowers both error rates. |
| Active challenge for everyone | Rejected: slower, annoying daily, and teaches attackers the challenge. |
| Depth / IR hardware | Rejected: not on budget phones. Face ID's TrueDepth is not exposed for third-party identity matching. |
| Store a thumbnail on failures | Rejected for Phase 1 (privacy positioning; FR-ATT-08 is P2 and decision D-4 is open). |

## Consequences

- We need an in-house **PAD test set**: prints (matte/glossy, A4 and passport), phone/tablet screen replays (several brands and brightness levels), video replays and paper masks. It must be collected with consent and kept off the repo ([ADR-0020](0020-testing-strategy-and-ml-evaluation.md)).
- Thresholds `T_live_high` and `T_live_low` are calibrated per model version and stored in the model card.
