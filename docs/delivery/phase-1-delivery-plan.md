# SyncGate — Phase 1 Technical Delivery Plan

| Field | Value |
|---|---|
| Scope | Phase 1 (v1 / GA): one phone, one gate, up to 25 workers, fully offline — [ADR-0001](../adr/0001-phase-1-scope-one-phone-25-workers.md) |
| Inputs | [PRD](../PRD.md) · [ADR index](../adr/README.md) · [Designs (iOS)](../designs/ios) · [Designs (Android)](../designs/android) |
| Plan owner | Product Manager + Tech Lead |
| Status | **Planning — in review.** Draft v1; not yet baselined. Dates, estimates, team sizes and the capacity check are proposals until the PM and Tech Lead sign off at the M0 kick-off. |
| Last updated | 24-10-2026 |
| Hard dates | GA release **Thu 29-04-2027** · DPDP enforcement **14-05-2027** |

---

## 1. Summary

Phase 1 is delivered in **four milestones** that match PRD §13. Work is run in **2-week sprints** (S1–S12) plus a release-candidate week.

| Milestone | Dates | Sprints | Goal | Exit decision |
|---|---|---|---|---|
| **M0 — Feasibility spike** | Mon 02-11-2026 → Fri 01-01-2027 | S1–S4 + buffer | Prove the face pipeline, kiosk behaviour and battery life on real budget phones; pick models and confirm the framework | **D-2** framework confirmed · model sourcing (TBD-L2) path chosen · candidate reference phones |
| **M1 — Alpha** | Mon 04-01-2027 → Fri 26-02-2027 | S5–S8 | End-to-end app: setup, enrolment, gate mode, liveness v1, shifts, corrections, Excel export, Hindi; encrypted storage | Internal use + **1 friendly factory** running for 2 weeks with no data loss |
| **M2 — Closed beta** | Mon 01-03-2027 → Fri 09-04-2027 | S9–S11 | Tally export, licensing, backup/restore (Drive), Gujarati + Tamil, DPDP pack, security hardening, pen test | **5–10 factories** (Surat, Tirupur) live ≥3 weeks; beta success bar met |
| **M3 — GA** | Mon 12-04-2027 → Fri 30-04-2027 | S12 + RC week | Fix beta and pen-test findings; certify devices; Punjabi + Marathi; store release; Ludhiana + Pune launch | **GA go/no-go** on Mon 26-04-2027; release Thu 29-04-2027 |

```
            Nov 2026        Dec 2026        Jan 2027        Feb 2027        Mar 2027        Apr 2027      May
            │S1   │S2   │S3   │S4   │buf│S5   │S6   │S7   │S8   │S9   │S10  │S11  │S12  │RC │
M0  ████████████████████████████████████
M1                                          ████████████████████████████████
M2                                                                          ████████████████████
M3                                                                                              ████████
Beta factories                                                    (1 friendly)  ███ 5–10 factories ██████
Pen test                                                                          ████████
Store review                                                                                        ███
DPDP enforcement ─────────────────────────────────────────────────────────────────────────────────────────▲ 14-05
```

### Sprint calendar

| Sprint | Start (Mon) | End (Fri) | Milestone |
|---|---|---|---|
| S1 | 02-11-2026 | 13-11-2026 | M0 |
| S2 | 16-11-2026 | 27-11-2026 | M0 |
| S3 | 30-11-2026 | 11-12-2026 | M0 |
| S4 | 14-12-2026 | 25-12-2026 | M0 |
| Buffer | 28-12-2026 | 01-01-2027 | M0 (D-2 report, holidays) |
| S5 | 04-01-2027 | 15-01-2027 | M1 |
| S6 | 18-01-2027 | 29-01-2027 | M1 |
| S7 | 01-02-2027 | 12-02-2027 | M1 |
| S8 | 15-02-2027 | 26-02-2027 | M1 |
| S9 | 01-03-2027 | 12-03-2027 | M2 |
| S10 | 15-03-2027 | 26-03-2027 | M2 |
| S11 | 29-03-2027 | 09-04-2027 | M2 |
| S12 | 12-04-2027 | 23-04-2027 | M3 |
| RC week | 26-04-2027 | 30-04-2027 | M3 (go/no-go Mon, release Thu) |

Public holidays in this window (Diwali week in November, Christmas–New Year, Republic Day, Holi, Good Friday) are absorbed by the capacity assumptions in §5.

---

## 2. Milestone detail

### M0 — Feasibility spike (02-11-2026 → 01-01-2027)

**Why:** the riskiest unknowns are physical. Can a ₹8–12k phone run detection + liveness + embedding in ≤700 ms, stay cool for 12 hours, and stay locked as a kiosk? Do we have legally usable models? Everything else is ordinary app work.

**In scope**
- `vision_bench` app on Flutter with native CameraX / AVFoundation pipelines and Texture preview ([ADR-0002](../adr/0002-cross-platform-framework-flutter.md)).
- Detector + quality metrics on both platforms. Interim embedding/PAD models for **benchmarking only** ([ADR-0006](../adr/0006-on-device-vision-pipeline.md)).
  > Non-commercial open weights may be used **only inside `vision_bench`**, never in an app build, and only after legal confirms that internal benchmarking is permitted.
- Model sourcing decision (train / license / commission) and legal review (TBD-L2).
- Evaluation harness v1 and the start of consented data collection ([ADR-0020](../adr/0020-testing-strategy-and-ml-evaluation.md)).
- Device lab bought; kiosk crash/reboot behaviour verified; 12 h soak and 4 h battery runs.
- Monorepo, CI and app shell skeleton ([ADR-0003](../adr/0003-app-architecture-and-repository-layout.md), [ADR-0021](../adr/0021-build-ci-cd-release-and-store-compliance.md)).
- Threat-model workshop ([ADR-0017](../adr/0017-security-hardening-and-privacy-dpdp.md)).
- **Foundations started early** (not blocked by the spike, see §5): `sg_ui` components and fonts; schema v1, append-only triggers and hash chains; ShiftEngine core; Excel builder; backup codec; l10n setup; Drift + SQLCipher; Keystore / Secure Enclave key managers; kiosk detection; monotonic-clock hooks; remaining screen designs; licence-server schema and Terraform; baseline embedding and PAD training.

**Exit criteria**

| # | Criterion | Evidence |
|---|---|---|
| M0-1 | Pipeline p95 ≤700 ms on ≥2 Android and ≥1 iOS candidate phones (25 enrolled) | `vision_bench` report |
| M0-2 | Preview ≥24 fps while analysing ≥10 fps; cold start to gate ≤5 s | Benchmark report |
| M0-3 | 12 h soak plugged in at ~30 °C and 4 h on battery complete without throttling below target | Soak log |
| M0-4 | Indian-script golden tests pass (hi, gu, ta, pa, mr) | CI |
| M0-5 | Kiosk behaviour after crash and reboot documented per OS and phone | QA note; ADR-0004/0018 updated |
| M0-6 | **D-2 decided**; ADR-0002 → Accepted (or superseded) | ADR PR |
| M0-7 | Embedding + PAD model path chosen, with legal sign-off on the route (not necessarily the final weights) | Decision memo |
| M0-8 | Candidate reference phones chosen | ADR-0019 update |

**Demo:** a worker walks up to a budget phone on a stand and is identified hands-free, in light and in a dim corridor, with the latency overlay visible.

### M1 — Alpha (04-01-2027 → 26-02-2027)

**In scope**
- Setup wizard (language, trial, first shift, camera check, kiosk lock, first worker).
- Modes and roles, PIN, OS biometric unlock, guard pick-from-list fallback ([ADR-0004](../adr/0004-single-device-gate-and-admin-modes.md)).
- Design-system components on both platforms ([ADR-0005](../adr/0005-design-system-and-platform-adaptive-ui.md)).
- Encrypted DB + TemplateVault + key management ([ADR-0010](../adr/0010-local-storage-and-encryption.md)); schema v1, append-only events, hash chains ([ADR-0011](../adr/0011-data-model-append-only-events.md)).
- Enrolment: details, notice & consent, multi-angle capture, duplicate check ([ADR-0008](../adr/0008-enrolment-and-template-management.md)).
- Matching with margin + multi-frame agreement ([ADR-0009](../adr/0009-face-matching-and-thresholds.md)); passive liveness v1 ([ADR-0007](../adr/0007-liveness-detection.md)).
- Shift engine, clock integrity, Today, daily and monthly views, exceptions and corrections ([ADR-0012](../adr/0012-time-shifts-and-attendance-rules-engine.md), [ADR-0015](../adr/0015-reports-and-payroll-export.md)).
- Excel export. Local-file backup (share sheet) so the friendly factory's data is safe.
- English + Hindi; recorded Hindi voice clips + TTS for names ([ADR-0016](../adr/0016-localization-voice-and-indian-formats.md)).
- Duty-cycled camera and wake lock ([ADR-0018](../adr/0018-power-thermal-and-reliability-on-a-phone.md)).
- Opt-in Sentry + encrypted on-device log ([ADR-0022](../adr/0022-telemetry-diagnostics-and-support.md)).
- Licence server: activate + check-in endpoints, KMS signing and update check running in staging ([ADR-0014](../adr/0014-licensing-and-licence-server.md)).

**Exit criteria**

| # | Criterion |
|---|---|
| M1-1 | All "M1" tasks in §4 done to the Definition of Done (§7) |
| M1-2 | Friendly factory has run gate mode for **10 working days**: zero lost events, manual-entry rate ≤10% |
| M1-3 | Shift-engine golden suite (≥60 scenarios) green; monthly Excel matches the owner's own register for the same days |
| M1-4 | Internal FAR/FRR on the evaluation set meets the M1 interim bar: FRR ≤4%, FAR ≤0.1% at N=25 |
| M1-5 | No Sev-1 defects open |

### M2 — Closed beta (01-03-2027 → 09-04-2027)

**In scope**
- Tally Prime XML + employee mapping; real Tally import QA.
- Licensing end to end: activation, check-in, states, transfer, lost phone, Play Integrity / App Attest, pinning.
- Backup to Google Drive, scheduled backups, reminders, restore, re-enrol queue, wipe command.
- Active liveness fallback, spoof-suspect exception, threshold calibration, fairness calibration, mask slot.
- Gujarati + Tamil (beta clusters). Punjabi + Marathi translations and voice prepared for GA.
- DPDP compliance pack, privacy settings, worker data summary, retention purge.
- Root/jailbreak checks, thermal handling, crash relaunch, paper register, OEM battery guidance.
- Diagnostic bundle; support playbook; setup videos.
- External **penetration test** and **biometric privacy review**.
- Store listings and privacy forms prepared; internal track / TestFlight distribution to beta factories.

**Beta success bar (exit criteria)**

| # | Criterion |
|---|---|
| M2-1 | ≥5 factories live ≥3 weeks; ≥80% completed setup without a support call (§3.3) |
| M2-2 | Manual-entry rate ≤5% of marks from week 2; not-recognised rate ≤3% |
| M2-3 | Zero confirmed proxy marks in spot checks; PAD APCER ≤2% per species on the test set |
| M2-4 | ≥95% of Tally exports import with no manual edits |
| M2-5 | Backup/restore drill passed at ≥2 beta factories (restore to a fresh phone) |
| M2-6 | Pen-test report received; all Sev-1/Sev-2 findings have fixes planned for S12 |

### M3 — GA (12-04-2027 → 30-04-2027)

**In scope:** pen-test and beta fixes, certification on reference phones, final model evaluation reports, Punjabi + Marathi live, store submission, staged rollout, Ludhiana + Pune launch readiness, support readiness.

**GA go/no-go (Mon 26-04-2027)** — all must be true (PRD §13 launch criteria, restated for Phase 1):

| # | Criterion |
|---|---|
| GA-1 | All P0 functional requirements complete on both platforms |
| GA-2 | NFR-PERF-01 (restated: 25 workers ≤3 min, ≤3 s per worker) and NFR-ACC-01..04 verified on certified phones in real factory conditions |
| GA-3 | No open Sev-1/Sev-2 security findings; biometric privacy review closed |
| GA-4 | Legal TBDs closed: TBD-L1 (legal basis), TBD-L2 (model licences), TBD-L3 (retention defaults) |
| GA-5 | Certified device list published |
| GA-6 | Store listings approved (or the sideload channel ready, if a store review is still pending) |
| GA-7 | Support playbook, WhatsApp line and videos live in all four launch languages |

---

## 3. Team and roles

### 3.1 Roles

| Code | Role | Main responsibilities | FTE M0 | M1 | M2 | M3 |
|---|---|---|---|---|---|---|
| PM | Product Manager | PRD, scope, prioritisation, beta programme, store listings, vendors, legal liaison, go/no-go | 1.0 | 1.0 | 1.0 | 1.0 |
| TL | Tech Lead / Mobile Architect (Flutter) | Architecture, ADRs, CI/CD, schema, code review, D-2, release management | 1.0 | 1.0 | 1.0 | 1.0 |
| FE | Flutter Engineers (×2, third joins 04-01-2027) | App UI, domain, data, exports, backup, l10n, integrations | 2.0 | 3.0 | 3.0 | 3.0 |
| AND | Android Native / Vision Engineer (Kotlin) | CameraX, LiteRT, TemplateVault, Keystore, kiosk, integrity, power | 1.0 | 1.0 | 1.0 | 1.0 |
| IOS | iOS Native / Vision Engineer (Swift) | AVFoundation, LiteRT, TemplateVault, Secure Enclave, Guided Access, App Attest | 1.0 | 1.0 | 1.0 | 1.0 |
| ML | ML Engineer (face recognition and PAD) | Models, training, quantisation, thresholds, evaluation, model cards | 1.0 | 1.0 | 1.0 | 1.0 |
| MLD | ML Data & Evaluation Engineer | Consented data collection, PAD attack sets, labelling, fairness slices | 0.5 | 0.5 | 0.5 | 0.5 |
| BE | Backend Engineer (Go) | Licence server, infra, KMS, support console | 0.5 | 0.5 | 0.5 | 0.5 |
| QA | QA Engineer | Device lab, test plans, golden baselines, soak tests, Tally QA, certification | 0.5 | 1.0 | 1.0 | 1.0 |
| DES | Product Designer | Remaining screens, icons, design QA, store graphics | 0.5 | 0.5 | 0.5 | 0.5 |
| CS | Field Ops / Customer Success | Beta recruitment, on-site onboarding, support playbook, videos, resellers | 0.0 | 1.0 | 1.0 | 1.0 |
| LEG | Legal counsel (external) | DPDP review, TBD-L1/L2/L3, notices, model licences | on call | | | |
| SEC | Security vendor (external) | Pen test, biometric privacy review | — | — | booked | fixes verified |
| VEN | Localisation & voice vendor (external) | Translations, voice recording | — | Hindi | 4 languages | — |

Core team: **≈10 FTE in M0, ≈12 FTE from M1** (with the third Flutter engineer and full-time customer success), plus external vendors. A conditional **0.5 FTE contract ML engineer** is added for M1–M2 if models are trained in-house (§5).

### 3.2 RACI for key decisions

| Decision / deliverable | PM | TL | ML | AND/IOS | FE | QA | LEG | CS |
|---|---|---|---|---|---|---|---|---|
| D-2 framework confirmation (end M0) | C | **A/R** | C | R | R | C | — | — |
| Model sourcing / TBD-L2 | C | C | **R** | C | — | — | **A** | — |
| Thresholds and model release | I | C | **A/R** | C | — | C | — | — |
| Pricing and the 25-worker limit (D-3) | **A/R** | C | — | — | — | — | C | C |
| Tally scope (D-5) | **A** | C | — | — | R | C | — | C |
| DPDP notice text and legal basis (TBD-L1) | R | I | — | — | I | — | **A** | — |
| Retention defaults (TBD-L3) | R | C | — | — | I | — | **A** | — |
| Beta factory selection | **A** | I | — | — | — | — | — | R |
| GA go/no-go | **A** | R | R | R | R | R | C | C |

(A = accountable, R = responsible, C = consulted, I = informed)

---

## 4. Epics and tasks (one epic per ADR)

Estimates are in **ideal person-days (d)** for the named role. External vendor days (LEG, SEC, VEN) are tracked but not counted against team capacity. "Dep." lists the tasks a task waits on.

### E01 — Product scope and programme · [ADR-0001](../adr/0001-phase-1-scope-one-phone-25-workers.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E01-T01 | Update PRD to v0.3: phone, ≤25 workers, restated targets | PM | 2 | M0 | — |
| E01-T02 | Sales qualification checklist + trial agreement | PM | 2 | M0 | E01-T01 |
| E01-T03 | Pricing decision and whether 25 workers is a licence limit (D-3) | PM | 3 | M1 | owner interviews |
| E01-T04 | Beta success metrics + weekly scorecard | PM | 2 | M1 | — |
| E01-T05 | Recruit 8–10 beta factories in Surat and Tirupur | CS | 6 | M1 | E01-T02 |
| E01-T06 | GA launch plan for Ludhiana + Pune (channels, resellers, associations) | PM | 4 | M2 | — |

### E02 — Framework spike · [ADR-0002](../adr/0002-cross-platform-framework-flutter.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E02-T01 | `vision_bench` Flutter shell with latency/fps overlay and CSV export | FE | 3 | M0 | E03-T01 |
| E02-T02 | Pigeon event contract v0 (FaceSeen, QualityHint, Match, NoMatch, Stats) | TL | 2 | M0 | — |
| E02-T03 | CameraX ImageAnalysis + Texture preview | AND | 4 | M0 | E02-T02 |
| E02-T04 | AVFoundation capture + Texture preview | IOS | 4 | M0 | E02-T02 |
| E02-T05 | Interim models end to end on Android (benchmark only) | AND | 3 | M0 | E06-T04 |
| E02-T06 | Interim models end to end on iOS (benchmark only) | IOS | 3 | M0 | E06-T05 |
| E02-T07 | Indian-script rendering golden tests (hi, gu, ta, pa, mr) | FE | 2 | M0 | — |
| E02-T08 | Measure cold start, install size, fps and 4 h battery on candidate phones | QA | 4 | M0 | E02-T05, E02-T06 |
| E02-T09 | D-2 decision report; update ADR-0002 | TL | 2 | M0 | E02-T08 |

### E03 — Architecture and repository · [ADR-0003](../adr/0003-app-architecture-and-repository-layout.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E03-T01 | Melos monorepo, FVM pin, analysis options, package skeletons | TL | 2 | M0 | — |
| E03-T02 | Import-boundary lint + CI rule (domain must stay pure) | TL | 1 | M0 | E03-T01 |
| E03-T03 | App shell: Riverpod, go_router, mode-aware redirect | FE | 3 | M0 | E03-T01 |
| E03-T04 | Flavours dev / staging / prod and env files | FE | 2 | M0 | E03-T03 |
| E03-T05 | Result/failure types and logging facade (enumerated codes) | TL | 1 | M0 | E03-T01 |
| E03-T06 | Architecture walkthrough + onboarding guide | TL | 1 | M1 | — |

### E04 — Modes, roles and kiosk · [ADR-0004](../adr/0004-single-device-gate-and-admin-modes.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E04-T01 | AppModeController, auto-return timer, "Gate is paused" banner | FE | 4 | M1 | E03-T03 |
| E04-T02 | Users, PIN (Argon2id), lockout, recovery code | FE | 4 | M1 | E10-T01 |
| E04-T03 | OS biometric unlock (`local_auth`) | FE | 1 | M1 | E04-T02 |
| E04-T04 | Role guards on routes and actions | FE | 2 | M1 | E04-T02 |
| E04-T05 | Android app pinning: start, detect, warnings | AND | 3 | M0 | — |
| E04-T06 | iOS Guided Access detection and warnings | IOS | 2 | M0 | — |
| E04-T07 | Reboot prompt + `BOOT_COMPLETED` notification | AND | 2 | M2 | E04-T05 |
| E04-T08 | Guard pick-from-list fallback, reasons, daily cap | FE | 3 | M1 | E11-T04 |
| E04-T09 | Verify kiosk behaviour on crash and reboot (candidate phones) | QA | 2 | M0 | E19-T01 |
| E04-T10 | Gate screens: scanning, matched, not recognised, cooldown | FE | 5 | M1 | E05-T02 |

### E05 — Design system and UI · [ADR-0005](../adr/0005-design-system-and-platform-adaptive-ui.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E05-T01 | `sg_ui` token package | FE | 2 | M0 | E03-T01 |
| E05-T02 | Adaptive components (top bar, nav bar, button, switch, field, sheet, segmented, select row, chips) | FE | 10 | M0 | E05-T01 |
| E05-T03 | Bundle and subset fonts; fallback chain | FE | 2 | M0 | E05-T01 |
| E05-T04 | Icon set (stroke icons → Flutter) | DES | 2 | M1 | — |
| E05-T05 | Design remaining screens: first-shift setup, shift rules, worker profile, settings, roles, restore, Tally mapping, DPDP pack | DES | 10 | M0 | — |
| E05-T06 | Golden baselines for both platforms | QA | 3 | M1 | E05-T02 |
| E05-T07 | Design QA pass — alpha | DES | 2 | M1 | — |
| E05-T08 | Design QA pass — beta | DES | 2 | M2 | — |
| E05-T09 | Design QA pass — RC + store graphics | DES | 3 | M3 | — |

### E06 — On-device vision pipeline · [ADR-0006](../adr/0006-on-device-vision-pipeline.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E06-T01 | Pipeline spec (pre-processing, alignment, events, thresholds) | ML | 3 | M0 | — |
| E06-T02 | Model sourcing options + decision memo (TBD-L2) | ML | 5 | M0 | — |
| E06-T03 | Legal review of model and dataset licences | LEG | 5 | M0 | E06-T02 |
| E06-T04 | Detector + quality metrics — Android | AND | 6 | M0 | E02-T03 |
| E06-T05 | Detector + quality metrics — iOS | IOS | 6 | M0 | E02-T04 |
| E06-T06 | Alignment + embedding inference — Android | AND | 4 | M1 | E06-T04 |
| E06-T07 | Alignment + embedding inference — iOS | IOS | 4 | M1 | E06-T05 |
| E06-T08a | Training pipeline + baseline embedding model on commercially licensed data | ML | 6 | M0 | E06-T03 |
| E06-T08b | Fine-tune the embedding model on consented South Asian / mask / PPE data | ML | 14 | M1 | E06-T08a, E20-T05b |
| E06-T09 | INT8 quantisation + accuracy regression check | ML | 4 | M1 | E06-T08b |
| E06-T10 | Exposure, backlight metering, fill-light trigger — Android | AND | 3 | M1 | E06-T04 |
| E06-T11 | Exposure, backlight metering, fill-light trigger — iOS | IOS | 3 | M1 | E06-T05 |
| E06-T12 | Fill-light and quality-hint UI | FE | 2 | M1 | E04-T10 |
| E06-T13 | Dirty-lens monitor | ML | 2 | M2 | E06-T06 |
| E06-T14 | Model cards + versioned model packaging | ML | 2 | M2 | E06-T09 |
| E06-T15 | Model-version stamping and migration — Android | AND | 2 | M3 | E10-T04 |
| E06-T16 | Model-version stamping and migration — iOS | IOS | 2 | M3 | E10-T05 |
| E06-T17 | Cross-platform parity test on recorded clips | QA | 3 | M1 | E06-T06, E06-T07 |

### E07 — Liveness · [ADR-0007](../adr/0007-liveness-detection.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E07-T01 | Capture PAD attack set (print, screen, video, cut-outs) | MLD | 8 | M0 | E20-T06 |
| E07-T02a | Baseline passive PAD model on the M0 attack set | ML | 5 | M0 | E07-T01 |
| E07-T02b | Train production passive PAD model (more species, phones, lighting) | ML | 10 | M1 | E07-T02a |
| E07-T03 | Temporal cues — Android | AND | 4 | M1 | E06-T04 |
| E07-T04 | Temporal cues — iOS | IOS | 4 | M1 | E06-T05 |
| E07-T05 | Screen-border context detector | ML | 4 | M2 | E07-T02b |
| E07-T06 | Active fallback (blink / turn) — Android | AND | 2 | M2 | E07-T03 |
| E07-T07 | Active fallback (blink / turn) — iOS | IOS | 2 | M2 | E07-T04 |
| E07-T08 | Active fallback UI + voice | FE | 2 | M2 | E16-T06 |
| E07-T09 | Threshold calibration + APCER/BPCER report | ML | 3 | M2 | E07-T02b, E20-T04 |
| E07-T10 | Spoof-suspect exception | FE | 1 | M2 | E11-T04 |

### E08 — Enrolment and templates · [ADR-0008](../adr/0008-enrolment-and-template-management.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E08-T01 | Worker details form, validation, under-18 block | FE | 4 | M1 | E05-T02 |
| E08-T02 | Notice & consent screen + consent record | FE | 3 | M1 | E11-T01 |
| E08-T03 | Face-capture UI (ring, angles, hints) | FE | 4 | M1 | E05-T02 |
| E08-T04 | Native capture session + quality gating — Android | AND | 3 | M1 | E06-T06 |
| E08-T05 | Native capture session + quality gating — iOS | IOS | 3 | M1 | E06-T07 |
| E08-T06 | Duplicate detection — Android | AND | 1 | M1 | E09-T01 |
| E08-T07 | Duplicate detection — iOS | IOS | 1 | M1 | E09-T02 |
| E08-T08 | Duplicate warning + owner override UI | FE | 2 | M1 | E08-T06 |
| E08-T09 | Adaptive template slot — Android | AND | 2 | M2 | E09-T01 |
| E08-T10 | Adaptive template slot — iOS | IOS | 2 | M2 | E09-T02 |
| E08-T11 | Re-enrol, deactivate, delete, 90-day template auto-delete | FE | 3 | M1 | E10-T04 |
| E08-T12 | Workers list with statuses (design 11) | FE | 3 | M1 | E05-T02 |

### E09 — Matching · [ADR-0009](../adr/0009-face-matching-and-thresholds.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E09-T01 | Matcher with margin + multi-frame agreement — Android | AND | 3 | M1 | E10-T04 |
| E09-T02 | Matcher with margin + multi-frame agreement — iOS | IOS | 3 | M1 | E10-T05 |
| E09-T03 | Mask-slot logic and calibration | ML | 3 | M2 | E06-T09 |
| E09-T04 | Strict / Standard / Relaxed presets | FE | 1 | M2 | — |
| E09-T05 | Fairness calibration by demographic slice | ML | 4 | M2 | E20-T04 |

### E10 — Local storage and encryption · [ADR-0010](../adr/0010-local-storage-and-encryption.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E10-T01 | Drift + SQLCipher integration | FE | 2 | M0 | E10-T02, E10-T03 |
| E10-T02 | KeyManager — Android Keystore / StrongBox | AND | 3 | M0 | — |
| E10-T03 | KeyManager — iOS Secure Enclave / Keychain | IOS | 3 | M0 | — |
| E10-T04 | TemplateVault encrypted files — Android | AND | 3 | M1 | E10-T02 |
| E10-T05 | TemplateVault encrypted files — iOS | IOS | 3 | M1 | E10-T03 |
| E10-T06 | Exclude data from OS backups — Android | AND | 1 | M0 | — |
| E10-T07 | Exclude data from OS backups — iOS | IOS | 1 | M0 | — |
| E10-T08 | Integrity checks + WAL durability tests | FE | 2 | M1 | E10-T01 |
| E10-T09 | Crypto-shred wipe — Android | AND | 1 | M2 | E10-T02 |
| E10-T10 | Crypto-shred wipe — iOS | IOS | 1 | M2 | E10-T03 |

### E11 — Data model · [ADR-0011](../adr/0011-data-model-append-only-events.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E11-T01 | Schema v1 + ERD | TL | 3 | M0 | — |
| E11-T02 | Append-only triggers | FE | 1 | M0 | E11-T01 |
| E11-T03 | Hash chains + incremental verification | FE | 3 | M0 | E11-T01 |
| E11-T04 | Corrections and exceptions model | FE | 3 | M0 | E11-T01 |
| E11-T05 | Retention purge job | FE | 2 | M2 | E11-T01 |
| E11-T06 | Worker data summary (printable) | FE | 3 | M2 | E12-T02 |
| E11-T07 | Migration test harness | FE | 2 | M2 | E11-T01 |

### E12 — Time, shifts and rules engine · [ADR-0012](../adr/0012-time-shifts-and-attendance-rules-engine.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E12-T01 | Rules model + `effective_from` versioning | FE | 2 | M0 | E11-T01 |
| E12-T02 | ShiftEngine core (attribution, night shifts, OT, half day, missing OUT) | FE | 6 | M0 | E12-T01 |
| E12-T03 | Direction resolver + cooldown | FE | 2 | M0 | E12-T01 |
| E12-T04 | Golden scenario suite (≥60 cases) | QA | 4 | M1 | E12-T02 |
| E12-T05 | Clock integrity: monotonic, boot ID, time-change events — Android | AND | 2 | M0 | — |
| E12-T06 | Clock integrity: monotonic, boot ID, time-change events — iOS | IOS | 2 | M0 | — |
| E12-T07 | Clock-jump detection + exceptions (Dart) | FE | 2 | M1 | E12-T05, E12-T06 |
| E12-T08 | First-shift setup and shift-rules screens | FE | 4 | M1 | E05-T05 |
| E12-T09 | Today dashboard + daily view | FE | 3 | M1 | E12-T02 |

### E13 — Backup, restore, device replacement · [ADR-0013](../adr/0013-backup-restore-and-device-replacement.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E13-T01 | `.sgbackup` codec (Argon2id, AES-GCM, zstd, manifest) | FE | 4 | M0 | E11-T01 |
| E13-T02 | Backup passphrase UX + wrapped storage | FE | 2 | M1 | E13-T01 |
| E13-T03 | Share-sheet backup + Save to device | FE | 1 | M1 | E13-T01 |
| E13-T04 | Google Cloud project, OAuth consent screen, `drive.file` verification | PM | 2 | M1 | — |
| E13-T05 | Google Sign-In + Drive upload, keep last 10 | FE | 3 | M2 | E13-T04 |
| E13-T06 | Scheduled backup — Android WorkManager | AND | 2 | M2 | E13-T05 |
| E13-T07 | Scheduled backup — iOS BGProcessingTask | IOS | 2 | M2 | E13-T05 |
| E13-T08 | Backup reminders (7 / 14 days) | FE | 1 | M2 | E13-T01 |
| E13-T09 | Restore flow, verification, re-enrol queue | FE | 5 | M2 | E13-T01 |
| E13-T10 | Lost-phone report + wipe-command handling in the app | FE | 2 | M2 | E14-T06b |
| E13-T11 | Incident record + breach-notification template (with legal) | PM | 2 | M2 | — |

### E14 — Licensing and licence server · [ADR-0014](../adr/0014-licensing-and-licence-server.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E14-T01 | Token spec (PASETO v4.public), claims, key-rotation plan | TL | 2 | M1 | — |
| E14-T02 | LicenceVerifier + licence state machine | FE | 3 | M2 | E14-T01 |
| E14-T03 | Device key + Play Integrity | AND | 3 | M2 | E14-T01 |
| E14-T04 | Device key + App Attest | IOS | 3 | M2 | E14-T01 |
| E14-T05 | Licence UI: activation, trial, banners, states | FE | 3 | M2 | E14-T02 |
| E14-T06a | Go server: activate + check-in | BE | 6 | M1 | E14-T07 |
| E14-T06b | Go server: transfer, report-lost, keys, wipe command | BE | 4 | M2 | E14-T06a |
| E14-T07 | PostgreSQL schema + migrations | BE | 2 | M0 | — |
| E14-T08 | KMS signing + rotation | BE | 2 | M1 | E14-T06a |
| E14-T09 | Terraform: ap-south-1 staging and prod | BE | 4 | M0 | — |
| E14-T10 | Internal support console (SSO) | BE | 4 | M2 | E14-T06b |
| E14-T11 | Certificate pinning — Android | AND | 1 | M2 | E14-T09 |
| E14-T12 | Certificate pinning — iOS | IOS | 1 | M2 | E14-T09 |
| E14-T13 | Update-check endpoint (sideload channel) | BE | 1 | M1 | E14-T06a |
| E14-T14 | Server security + load tests | BE | 2 | M3 | E14-T06b |

### E15 — Reports and payroll export · [ADR-0015](../adr/0015-reports-and-payroll-export.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E15-T01 | Monthly muster roll screen | FE | 3 | M1 | E12-T02 |
| E15-T02 | Exceptions screen + correction sheet + audit entries | FE | 4 | M1 | E11-T04 |
| E15-T03 | Excel builder + column templates | FE | 4 | M0 | E12-T02 |
| E15-T04 | Tally Prime XML builder + employee mapping UI | FE | 5 | M2 | E12-T02 |
| E15-T05 | Tally import QA on real Tally Prime | QA | 3 | M2 | E15-T04, E15-T07 |
| E15-T06 | Export log, share sheet, role checks | FE | 1 | M1 | E15-T03 |
| E15-T07 | Buy Tally Prime licence + build sample company data | PM | 1 | M1 | — |

### E16 — Localisation and voice · [ADR-0016](../adr/0016-localization-voice-and-indian-formats.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E16-T01 | gen-l10n setup + "no hard-coded strings" lint | FE | 2 | M0 | E03-T03 |
| E16-T02 | Hindi translation + field review | VEN | 5 | M1 | E16-T01 |
| E16-T03 | Gujarati + Tamil translation (beta clusters) | VEN | 6 | M2 | E16-T02 |
| E16-T04 | Punjabi + Marathi translation (GA clusters) | VEN | 6 | M2 | E16-T02 |
| E16-T05 | Hindi voice clips (script + studio) | VEN | 1 | M1 | — |
| E16-T06 | Audio player, TTS wrapper, voice-availability check | FE | 3 | M1 | E16-T05 |
| E16-T07 | Voice clips for Gujarati, Tamil, Punjabi, Marathi | VEN | 4 | M2 | E16-T03, E16-T04 |
| E16-T08 | Transliteration-aware worker search | FE | 2 | M2 | E08-T12 |
| E16-T09 | Legal review of notices in all languages | LEG | 4 | M2 | E16-T03, E16-T04 |
| E16-T10 | Text-scale (130%) + longest-locale QA | QA | 2 | M2 | E16-T03 |
| E16-T11 | Localisation coordination with vendors | PM | 4 | M2 | — |

### E17 — Security and DPDP · [ADR-0017](../adr/0017-security-hardening-and-privacy-dpdp.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E17-T01 | Threat-model workshop + OWASP MASVS mapping | TL | 2 | M0 | — |
| E17-T02 | Integrity / root checks — Android | AND | 2 | M2 | — |
| E17-T03 | Integrity / jailbreak checks — iOS | IOS | 2 | M2 | — |
| E17-T04 | `FLAG_SECURE` + network allow-list — Android | AND | 1 | M1 | — |
| E17-T05 | App-switcher blur + ATS — iOS | IOS | 1 | M1 | — |
| E17-T06 | Outbound-schema CI check (no biometric or worker fields) | TL | 2 | M1 | E21-T01 |
| E17-T07 | DPDP compliance pack content | PM | 3 | M2 | E17-T11 |
| E17-T08 | Privacy settings + DPDP pack screen | FE | 2 | M2 | E17-T07 |
| E17-T09 | External penetration test (app + server) | SEC | 10 | M2 | E14-T06b |
| E17-T10 | Fix pen-test findings | TL | 5 | M3 | E17-T09 |
| E17-T11 | Legal sign-off: TBD-L1 and TBD-L3 | LEG | 5 | M2 | — |
| E17-T12 | External biometric privacy review | SEC | 5 | M2 | E08-T02 |

### E18 — Power, thermal and reliability · [ADR-0018](../adr/0018-power-thermal-and-reliability-on-a-phone.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E18-T01 | Duty-cycle state machine — Android | AND | 3 | M1 | E06-T04 |
| E18-T02 | Duty-cycle state machine — iOS | IOS | 3 | M1 | E06-T05 |
| E18-T03 | Thermal monitoring + throttling — Android | AND | 1 | M2 | E18-T01 |
| E18-T04 | Thermal monitoring + throttling — iOS | IOS | 1 | M2 | E18-T02 |
| E18-T05 | Wake lock, dimming, unplugged warning | FE | 2 | M1 | E04-T10 |
| E18-T06 | OEM battery-optimisation guidance table + screens | AND | 2 | M3 | — |
| E18-T07 | Crash relaunch — Android | AND | 2 | M2 | E04-T09 |
| E18-T08 | Crash relaunch — iOS | IOS | 1 | M2 | E04-T09 |
| E18-T09 | Paper-register PDF + "Add from paper register" | FE | 3 | M2 | E11-T04 |
| E18-T10 | Soak (12 h) + battery (4 h) runs — M0 | QA | 2 | M0 | E02-T05 |
| E18-T11 | Soak + battery runs — beta build | QA | 2 | M2 | E18-T03 |
| E18-T12 | Soak + battery runs — RC on certified phones | QA | 2 | M3 | — |

### E19 — Supported devices · [ADR-0019](../adr/0019-supported-devices-and-os-versions.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E19-T01 | Market scan of best-selling budget phones + buy device lab (6 phones) | QA | 2 | M0 | — |
| E19-T02 | In-app hardware check + mini-benchmark (Dart) | FE | 2 | M2 | E06-T06 |
| E19-T03 | Hardware probe — Android | AND | 1 | M2 | — |
| E19-T04 | Hardware probe — iOS | IOS | 1 | M2 | — |
| E19-T05 | Certification runs on reference phones | QA | 5 | M3 | all features |
| E19-T06 | Publish certified list + accessory guide | PM | 2 | M3 | E19-T05 |

### E20 — Testing and ML evaluation · [ADR-0020](../adr/0020-testing-strategy-and-ml-evaluation.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E20-T01 | CI test stages (unit, golden, native) | TL | 2 | M0 | E21-T01 |
| E20-T02 | Patrol + fake camera feed (Dart side) | FE | 3 | M1 | E04-T10 |
| E20-T03 | Fake camera feed injection — Android | AND | 1 | M1 | E02-T03 |
| E20-T04 | Evaluation harness (1:N simulation, PAD, fairness) | ML | 6 | M0 | E06-T01 |
| E20-T05a | Consented data collection — cluster 1 (Surat) | MLD | 6 | M0 | E20-T06 |
| E20-T05b | Consented data collection — cluster 2 (Tirupur) | MLD | 6 | M1 | E20-T05a |
| E20-T06 | Data-handling and consent process for evaluation data | LEG | 2 | M0 | — |
| E20-T07 | Fake camera feed injection — iOS | IOS | 1 | M1 | E02-T04 |
| E20-T08 | Firebase Test Lab matrix | QA | 2 | M2 | — |
| E20-T09 | Beta metrics counters (on device) | FE | 2 | M2 | E11-T01 |
| E20-T10 | Test plans + regression suite — alpha | QA | 3 | M1 | — |
| E20-T11 | Test plans + regression suite — beta | QA | 3 | M2 | — |
| E20-T12 | Release evaluation reports (beta model) | ML | 2 | M2 | E07-T09 |
| E20-T13 | Release evaluation reports (GA model) | ML | 1 | M3 | E20-T12 |
| E20-T14 | Labelling and slice tagging of collected data | MLD | 5 | M1 | E20-T05a |

### E21 — Build, CI/CD and stores · [ADR-0021](../adr/0021-build-ci-cd-release-and-store-compliance.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E21-T01 | GitHub Actions: pr, nightly, release | TL | 3 | M0 | E03-T01 |
| E21-T02 | Fastlane match/supply + Android signing-key ceremony | TL | 3 | M1 | E21-T01 |
| E21-T03 | Play Console + App Store Connect + developer accounts | PM | 1 | M0 | — |
| E21-T04 | Store listings, Data safety, privacy labels, review notes, demo video | PM | 3 | M2 | E17-T07 |
| E21-T05 | Internal track / TestFlight distribution to beta factories | TL | 1 | M2 | E21-T02 |
| E21-T06 | Sideload channel + in-app update check | FE | 1 | M2 | E14-T13 |
| E21-T07 | Store submission + review buffer | PM | 2 | M3 | E21-T04 |
| E21-T08 | Staged-rollout runbook + release checklist | TL | 1 | M3 | — |

### E22 — Telemetry, diagnostics and support · [ADR-0022](../adr/0022-telemetry-diagnostics-and-support.md)

| ID | Task | Role | Est (d) | Milestone | Dep. |
|---|---|---|---|---|---|
| E22-T01 | Sentry (Dart + native) with scrubbing, opt-in | FE | 2 | M1 | E03-T05 |
| E22-T02 | Encrypted on-device log | FE | 2 | M1 | E10-T01 |
| E22-T03 | Diagnostic bundle + in-app preview | FE | 3 | M2 | E22-T02 |
| E22-T04 | Support playbook, WhatsApp Business line, reply macros (hi/en) | CS | 4 | M1 | — |
| E22-T05 | Setup-video scripts, shoot plan and review (Hindi + regional) | CS | 2 | M2 | E05-T05 |
| E22-T05b | Setup-video production and editing | VEN | 3 | M2 | E22-T05 |
| E22-T06 | Beta field support (on-site onboarding and weekly visits) | CS | 15 | M2 | E01-T05 |
| E22-T07 | GA support readiness + reseller training | CS | 5 | M3 | E22-T04 |
| E22-T08 | Friendly-factory onboarding and support (alpha) | CS | 4 | M1 | E01-T05 |

---

## 5. Capacity check

**Assumptions**
- Working days per milestone for 1 FTE, after public holidays and ~10% leave: **M0 36 · M1 34 · M2 25 · M3 12**.
- Focus factor **0.8** (meetings, reviews, support), so planned capacity = FTE × days × 0.8.
- Estimates are ideal person-days from §4, summed by a script over the 218 task rows (no hand totals).
- External roles (LEG, SEC, VEN) are vendor days and are not counted against team capacity.

**Load vs capacity (planned days / available days, utilisation)**

| Role | M0 | M1 | M2 | M3 | Total load |
|---|---|---|---|---|---|
| PM | 5 / 28.8 (17%) | 8 / 27.2 (29%) | 16 / 20 (80%) | 4 / 9.6 (42%) | 33 |
| TL | 18 / 28.8 (62%) | 8 / 27.2 (29%) | 1 / 20 (5%) | 6 / 9.6 (62%) | 33 |
| FE (2 → 3) | 53 / 57.6 (92%) | 74 / 81.6 (91%) | 48 / 60 (80%) | 0 / 28.8 (0%) | 175 |
| AND | 22 / 28.8 (76%) | 26 / 27.2 (96%) | 19 / 20 (95%) | 4 / 9.6 (42%) | 71 |
| IOS | 21 / 28.8 (73%) | 26 / 27.2 (96%) | 16 / 20 (80%) | 2 / 9.6 (21%) | 65 |
| ML | 25 / 28.8 (87%) | **28 / 27.2 (103%)** | **20 / 20 (100%)** | 1 / 9.6 (10%) | 74 |
| MLD | 14 / 14.4 (97%) | 11 / 13.6 (81%) | 0 / 10 (0%) | 0 / 4.8 (0%) | 25 |
| BE | 6 / 14.4 (42%) | 9 / 13.6 (66%) | 8 / 10 (80%) | 2 / 4.8 (42%) | 25 |
| QA | 10 / 14.4 (69%) | 13 / 27.2 (48%) | 12 / 20 (60%) | 7 / 9.6 (73%) | 42 |
| DES | 10 / 14.4 (69%) | 4 / 13.6 (29%) | 2 / 10 (20%) | 3 / 4.8 (62%) | 19 |
| CS | — | 14 / 27.2 (51%) | 17 / 20 (85%) | 5 / 9.6 (52%) | 36 |
| *LEG (vendor)* | 7 | 0 | 9 | 0 | 16 |
| *SEC (vendor)* | 0 | 0 | 15 | 0 | 15 |
| *VEN (vendor)* | 0 | 6 | 19 | 0 | 25 |

**How the plan was balanced.** A first pass put M1 at 215% for Flutter, 129% Android, 125% iOS and 143% ML, while M0 sat mostly idle. To fix this:
- **Work moved into M0** because it does not depend on the camera spike:
  - pure-Dart work: shift engine core, data model and hash chains, Excel builder, backup codec, l10n setup, flavours;
  - design-system components and fonts;
  - Keystore / Secure Enclave key managers, kiosk detection and monotonic-clock hooks;
  - the remaining screen designs;
  - licence-server schema and infrastructure.
- **ML training split.** Baseline embedding and PAD models are trained in M0; fine-tuning happens in M1.
- **Team changes:**
  - **a third Flutter engineer joins on 04-01-2027**;
  - the backend engineer starts at 0.5 FTE in M0;
  - customer success goes to 1.0 FTE from M1;
  - setup-video production moves to a vendor.

**What the numbers say**
1. **M3 engineering capacity is deliberately left empty.** Flutter, Android and iOS have ~40 person-days free in S12 + RC week. That is the budget for beta defects and pen-test fixes (E17-T10). Do not plan features into it.
2. **ML is the bottleneck** (103% in M1, 100% in M2, 87% in M0). If the TBD-L2 route is "train in-house", add a **0.5 FTE contract ML engineer for M1–M2**. If the route is "license an SDK", training tasks shrink and ML load drops below 70%. Decide with the model route on 01-01-2027 (see R-01, R-21).
3. **Android and iOS run at 95–96% in M1.** Any slip in the vision spike moves straight into M1. The parity test (E06-T17) and vision sync are the early warning.
4. **MLD is at 97% in M0.** Data collection depends on factory access and consent logistics. Start recruiting participants in S1.
5. The PM and TL have spare capacity in M1–M2. It is earmarked for beta operations, code review, unplanned legal work and store issues.

---

## 6. Critical path and key dependencies

```
E06-T02 model sourcing ──► E06-T03 legal review ──► E06-T08a baseline (M0) ──► E06-T08b fine-tune (M1) ──► E06-T09 quantise
        │                                                                          ▲                       │
        │                                              E20-T05a/b consented data ──┘                       ▼
        │                                                                          E09-T05 fairness · E20-T12 eval report
        ▼                                                                                                  │
E07-T01 PAD data ──► E07-T02a baseline PAD (M0) ──► E07-T02b production PAD (M1) ──► E07-T09 calibrate ────┤
                                                                                            ▼
E14-T06a/b licence server ──► E17-T09 pen test (M2) ──► E17-T10 fixes (S12) ──► GA go/no-go 26-04
E21-T04 store forms ──► E21-T07 submission (S12) ──► store review ──────────────────────────┘
```

| Dependency | Needed by | Lead time / risk | Owner |
|---|---|---|---|
| Model licence route (TBD-L2) | Mid-M0 for the baseline (E06-T08a); hard stop 01-01-2027 for fine-tuning (E06-T08b) | External legal; vendor negotiation if licensing | ML + LEG |
| Consented evaluation data (≥300 identities) | M1 training, M2 fairness | Field logistics, consent forms in local languages | MLD |
| Device lab purchase | S1 | Delivery ~1 week | QA |
| Tally Prime licence + sample company | M2 (E15-T05) | Purchase | PM |
| Google OAuth consent screen verification for `drive.file` | M2 Drive backup | Verification can take days to weeks | PM |
| Pen-test vendor booking | Book in M1 for a test in S10–S11 | 4–6 week booking lead time | PM / TL |
| Apple and Google developer accounts (organisation, D-U-N-S) | M0 | D-U-N-S can take 1–2 weeks | PM |
| Translation + voice vendor | Hindi in M1; others in M2 | Studio booking | PM |
| Beta factories signed | End of M1 | Owner availability around shift schedules | CS |

---

## 7. Ways of working

### Definition of Ready (task)
- Linked to an ADR and, where relevant, a PRD requirement ID.
- Designs exist for **both** platforms (if UI).
- Acceptance criteria and test approach written.
- Dependencies done or mocked.

### Definition of Done (task)
- Code reviewed by one engineer; native + Dart parts reviewed by the TL when they cross the Pigeon boundary.
- Unit / widget / golden tests added and green; golden updates approved by design.
- Works on one Android and one iOS lab phone.
- No new analyzer warnings; import-boundary and outbound-schema checks pass.
- Strings externalised; English + Hindi present.
- Audit log entries added for any admin action.
- Docs / ADR updated if a decision changed.

### Cadence

| Ritual | When | Who |
|---|---|---|
| Sprint planning / review / retro | Every 2 weeks (Mon / Fri) | Core team |
| Stand-up | Daily, 15 min | Core team |
| Vision sync (Android ⇄ iOS ⇄ ML parity) | Twice a week | AND, IOS, ML, TL |
| Risk review | Weekly, 30 min | PM, TL |
| Beta factory check-in | Weekly per factory (M2) | CS, PM |
| Milestone gate review | End of each milestone | All + stakeholders |

### Decision points

| Date | Decision | Input |
|---|---|---|
| Fri 01-01-2027 | D-2 framework; model route (TBD-L2) | M0 report |
| Fri 15-01-2027 | D-3 pricing, 25-worker limit | Owner interviews |
| Fri 26-02-2027 | M1 → M2 gate; beta list final | Alpha report |
| Fri 12-03-2027 | D-5 Tally scope confirmed | Beta feedback |
| Fri 09-04-2027 | M2 → M3 gate | Beta scorecard, pen-test report |
| Mon 26-04-2027 | **GA go/no-go** | GA criteria |

---

## 8. Risk register

Scoring: Likelihood (L) and Impact (I) from 1 (low) to 5 (high); score = L × I.

| ID | Risk | L | I | Score | Owner | Mitigation | Trigger → contingency |
|---|---|---|---|---|---|---|---|
| R-01 | No commercially licensable embedding / PAD model in time (TBD-L2) | 3 | 5 | 15 | ML + LEG | Start sourcing in S1; parallel tracks (train in-house vs licence an on-device SDK); legal review early | Route not cleared by 15-01-2027 → licence a commercial SDK for GA; keep in-house training for v1.1 |
| R-02 | Budget phones miss the ≤700 ms / thermal targets | 2 | 4 | 8 | AND / IOS | Duty cycling; INT8; XNNPACK tuning; restrict certified list | M0-1 fails → smaller input sizes, drop to 128-d embedding, raise device minimum |
| R-03 | Accuracy short of target with masks / low light / helmets | 3 | 4 | 12 | ML | Mask slot; fill light; enrolment "wear what you wear at the gate"; field data | FRR >5% in beta → retrain with beta-like data (consented), adjust presets, LED-light accessory |
| R-04 | Spoofing gets through (photo / screen replay) | 2 | 5 | 10 | ML | Layered PAD + active fallback; spoof-suspect exceptions; PAD test set | APCER >2% → active fallback forced on; ship PAD update before GA |
| R-05 | Demographic fairness rule (≤1.5× FRR) fails | 2 | 4 | 8 | ML | Balanced data collection; per-slice evaluation every model build | Slice fails → targeted data + retrain; block release |
| R-06 | Kiosk escapes / app not relaunched after reboot or crash | 4 | 3 | 12 | AND / IOS | Detection + warnings; boot notification; owner education; paper fallback | Beta gate-uptime <99.5% → add Android device-owner (QR) option as an opt-in expert setup |
| R-07 | OEM battery killers stop scheduled backups / relaunch | 4 | 2 | 8 | AND | Battery-optimisation exemption; OEM guides; backup on Admin open | Backups missed in beta → backup when charging + on each Admin exit |
| R-08 | Single phone lost or broken; owner also loses the backup passphrase | 3 | 4 | 12 | PM | Backup reminders; passphrase print-out; Drive auto-backup; restore drills in beta | Incident in beta → strengthen onboarding; consider an optional owner-held recovery key on paper |
| R-09 | App-store rejection (face data, kiosk, battery-optimisation request) | 3 | 3 | 9 | PM | Early pre-review questions; clear disclosures and review notes; demo video | Rejected in S12 → GA via Play + sideload first, iOS a few days later |
| R-10 | Pen test finds a Sev-1 late | 2 | 4 | 8 | TL | Threat model in M0; MASVS checklist; MobSF in CI; pen test in S10–S11 (not S12) | Sev-1 open on 26-04 → no-go; hotfix sprint; GA still before 14-05 |
| R-11 | Vision code differs between Android and iOS (parity bugs) | 3 | 3 | 9 | TL / ML | Shared spec; parity test on recorded clips; twice-weekly vision sync | Parity test fails → fix before feature work continues |
| R-12 | Single-person knowledge in AND / IOS / ML roles (bus factor) | 3 | 4 | 12 | TL | Pairing, written specs, recorded walkthroughs; TL reviews native code | Person unavailable >1 week → contractor from a vetted list; scope cut per §9 |
| R-13 | Hindi / regional TTS voices missing or poor on target phones | 3 | 2 | 6 | FE | Recorded phrase clips always; TTS only for names; setup check | Coverage poor → names omitted from voice for that language |
| R-14 | Tally import fails on customer setups (versions, voucher types) | 3 | 3 | 9 | FE / QA | Configurable attendance types; real Tally QA; mapping UI | ≥5% failures in beta → per-customer template + Excel fallback |
| R-15 | Legal reading of DPDP changes requirements late (R-7 in PRD) | 2 | 4 | 8 | PM / LEG | Design for the stricter reading; configurable legal basis; notices versioned | Change after M2 → config/notice update, not code |
| R-16 | Google OAuth verification delays Drive backup | 2 | 2 | 4 | PM | Apply in M1; `drive.file` is a non-sensitive scope | Not verified by GA → ship with local-file backup only; Drive in v1.0.1 |
| R-17 | Beta recruitment slips or factories churn | 3 | 3 | 9 | CS | Recruit 10 for 5; friendly-factory referrals; on-site support | <5 live by 22-03 → extend beta into S12 with fewer factories, keep GA date |
| R-18 | Timeline compression: GA 29-04 leaves 2 weeks before DPDP enforcement | 3 | 4 | 12 | PM | Hard scope control; §9 cut list; gate reviews | Slip >1 week at M2 gate → apply the cut list; GA by 13-05 at the latest |
| R-19 | Customers outgrow 25 workers during beta | 2 | 2 | 4 | PM | Warn, don't block; capture demand for Phase 2 | Many requests → bring the Phase 2 tablet / multi-device plan forward |
| R-20 | Consent and handling of the ML evaluation data challenged | 2 | 4 | 8 | MLD / LEG | Written consent in local language, purpose-limited, deletion on request, access controls | Complaint → pause collection, legal review |
| R-21 | ML capacity: ML is planned at ~100% in M1–M2 (§5) | 4 | 4 | 16 | PM / ML | Baseline training pulled into M0; model route decided by 01-01-2027 | Route = in-house training → hire a 0.5 FTE contract ML engineer by 04-01-2027; route = licensed SDK → reassign training days to evaluation |
| R-22 | Third Flutter engineer not on board by 04-01-2027 | 3 | 4 | 12 | PM / TL | Start hiring in S1; vetted contractor list | Not hired by 18-01 → contractor; otherwise apply §9 cuts 1–3 and move E16-T08, E11-T06 to M3 |

---

## 9. Scope-cut list (if the schedule slips)

Cut in this order. None of these breaks a P0 requirement or a DPDP control.

| Order | Cut | Impact |
|---|---|---|
| 1 | Adaptive template slot (E08-T09/T10) | Slightly more re-enrolments over time |
| 2 | Transliteration-aware search (E16-T08) | Search by exact script only |
| 3 | Strict/Relaxed presets (E09-T04) — keep Standard | Less owner control |
| 4 | Scheduled Drive backup (E13-T06/T07) — keep manual Drive + share sheet | More reliance on reminders |
| 5 | Screen-border PAD detector (E07-T05) — keep L1, L2 and the active fallback | Slightly weaker screen-replay defence; active fallback forced on |
| 6 | Punjabi + Marathi at GA (E16-T04/T07) | Ludhiana and Pune launch in Hindi first; regional languages in v1.0.1 within 3 weeks |

**Never cut:** liveness L1/L2, encryption and key management, append-only audit, consent and notice, under-18 block, backups excluding templates, export never blocked by licence, Hindi.

---

## 10. Beta programme (M2)

| Item | Plan |
|---|---|
| Factories | 8–10 recruited, ≥5 live; Surat (Gujarati, textiles) and Tirupur (Tamil, knitwear); 8–25 workers each |
| Hardware | Owner's own phone if it passes the hardware check; else a loaner reference phone; stand + charger provided |
| Onboarding | On-site visit by CS: setup wizard (owner drives), first 5 enrolments, kiosk lock, backup passphrase printed |
| Cadence | Week 1: two visits; then a weekly call + a fortnightly visit |
| Data shared with us | Only the owner-exported diagnostic bundle (aggregate counters); no personal data |
| Weekly scorecard | Gate uptime, marks/day, manual-entry %, not-recognised %, liveness-active %, exceptions open, backups taken, support tickets, owner NPS (1 question) |
| Exit interview | Would you pay? At what price? What is missing? (feeds D-3) |

---

## 11. GA launch checklist (RC week)

- [ ] All GA criteria (§2, M3) signed off by the accountable owner
- [ ] Release build from tag; SHA-256 of AAB, APK and IPA recorded
- [ ] Play: staged rollout 10% ready; App Store: phased release ready
- [ ] Sideload APK published on the website with checksum
- [ ] Licence server prod: keys rotated, backups verified, alerts on, on-call rota set
- [ ] Certified device list + accessory guide live
- [ ] Support: WhatsApp line staffed in hi / en / gu / ta / pa / mr; playbook v1; videos published
- [ ] Reseller training done for Ludhiana and Pune
- [ ] DPDP compliance pack available in-app in all languages
- [ ] Model cards and evaluation reports archived for the GA models
- [ ] Rollback plan: halt rollout; previous build on the sideload channel; server is backward compatible with the last two app versions

---

## 12. Non-labour budget items (to estimate)

| Item | Notes |
|---|---|
| Device lab | ~6 phones (2–3 reference Android, 1 Android 9/10 best-effort, 2 iPhones), stands, chargers, USB LED lights |
| Beta loaner phones | Up to 5 reference phones |
| Developer accounts | Apple Developer Program (organisation), Google Play Console |
| Cloud | AWS ap-south-1: Fargate, RDS Postgres, KMS, backups (small at Phase 1 scale) |
| CI | GitHub Actions minutes incl. macOS runners; Firebase Test Lab |
| Crash reporting | Sentry plan (or self-hosted) |
| Tally Prime | Licence for QA |
| Model / SDK licence | Depends on the TBD-L2 route |
| Data collection | Participant compensation, consent forms, field logistics in two clusters |
| Localisation | Translation for 5 languages + legal review; voice studio sessions |
| Security | Penetration test + biometric privacy review |
| Legal | DPDP review, notices, model licences |
