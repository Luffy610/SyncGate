# ADR-0020: Test pyramid, device lab and a biometric evaluation harness

- **Status:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering, ML, QA
- **Related:** §3.3 metrics · NFR-PERF-*, NFR-ACC-01..08 · GA launch criteria (§13) · ADR-0002, ADR-0006, ADR-0007, ADR-0009, ADR-0012, ADR-0015

## Context

Two kinds of correctness matter:

1. **Software correctness**: shift maths, exports, encryption, migrations and UI on two platforms.
2. **Biometric performance**: FAR, FRR, liveness and fairness in real factory conditions.

Each needs its own tools.

## Decision

### 1. Software test pyramid

| Level | Tooling | Scope | Gate |
|---|---|---|---|
| Unit | `package:test` | `sg_domain`: shift engine golden scenarios ([ADR-0012](0012-time-shifts-and-attendance-rules-engine.md) §5), direction resolver, licence verifier, audit chain, export builders, backup codec | ≥90% line coverage on `sg_domain`; required on every PR |
| Data | `drift` in-memory + SQLCipher test DB | Repositories, triggers blocking UPDATE/DELETE, every schema migration from each previous version | Every PR |
| Widget + golden | `flutter_test`, `alchemist`/golden toolkit | Every `sg_ui` component and key screen, **for both iOS and Android themes**, in `en`, `hi` and the longest locale, at 1.0× and 1.3× text scale | Every PR |
| Native unit | JUnit (Kotlin), XCTest (Swift) | TemplateVault crypto, alignment maths, quality metrics, Pigeon contracts | Every PR (macOS runner for iOS) |
| Pipeline parity | Recorded frame sequences → both native pipelines | Same decisions (match/no-match/liveness) on Android and iOS for a fixed clip set | Nightly |
| Integration on device | **Patrol** (native dialogs, permissions) | Setup wizard, enrol → gate match (with recorded camera feed injected in debug builds), correction, export, backup/restore, licence states | Nightly on the device lab; required before release |
| Device matrix | **Firebase Test Lab** (Android), physical iPhones | Smoke on ~15 Android models incl. OEM skins; iOS on lab devices | Pre-release |
| Exports | Golden `.xlsx`/XML files + manual Tally Prime import | [ADR-0015](0015-reports-and-payroll-export.md) | Each release |
| Security | MobSF static scan, dependency audit (`osv-scanner`), outbound-schema check ([ADR-0017](0017-security-hardening-and-privacy-dpdp.md)) | — | Every PR (scan), pre-release (pen-test) |

### 2. Biometric evaluation harness (`ml/eval`, Python)

- Runs the **exact `.tflite` files** that ship, through the same preprocessing (shared spec, with Python and native implementations tested against each other).
- **Datasets** (never committed; provenance in `ml/datasets/README.md`):
  - *Gallery/probe set:* consented volunteers across launch clusters. Target ≥300 identities, balanced by skin tone (Monk scale), gender and age band, captured on reference phones. Conditions: normal light (≥150 lux), low light (30–50 lux), backlight, mask, helmet/cap, turban, scarf, glasses, dust film on the lens.
  - *PAD set:* print (matte/glossy), screen replay (≥5 phone/tablet models), video replay, paper cut-outs ([ADR-0007](0007-liveness-detection.md)).
- **Metrics:**
  - FAR / FRR at the operating threshold, simulated as **1:N with N = 25** galleries drawn randomly 10,000 times;
  - FRR per condition;
  - APCER/BPCER per attack species (ISO/IEC 30107-3 style);
  - FRR per demographic slice, with the **≤1.5× overall** rule ([ADR-0009](0009-face-matching-and-thresholds.md));
  - latency per stage on reference phones (from `vision_bench`).
- Output: an HTML/Markdown **evaluation report** attached to the model card. A model **cannot ship** unless it meets every target.

### 3. Field validation (beta, M2)

- 5–10 factories in Surat and Tirupur.
- Telemetry is **only** aggregate on-device counters (manual-entry rate, not-recognised rate, liveness-active rate, gate uptime). These are shown to the owner and shared with us only in an owner-exported diagnostic bundle ([ADR-0022](0022-telemetry-diagnostics-and-support.md)).
- Success bar: manual-entry rate ≤5% of marks after week 2; zero confirmed proxy marks in spot checks.

## Consequences

- CI needs a macOS runner for iOS builds and XCTest.
- The ML team owns a consent and data-handling process for evaluation data. It is reviewed by legal (it is also personal data).
