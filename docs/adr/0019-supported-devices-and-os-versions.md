# ADR-0019: Supported phones and OS versions; reference device certification

- **Status:** In review
- **Proposed outcome:** Proposed — the certified device list is fixed at the end of M0
- **Date:** 24-10-2026
- **Deciders:** Engineering, Product, Sales
- **Related:** FR-PLT-01, FR-PLT-03, FR-PLT-04 · NFR-HW-01..03 · TC-02 · ADR-0001, ADR-0006, ADR-0018

## Context

Phase 1 runs on **phones the owner already has or buys cheaply** ([ADR-0001](0001-phase-1-scope-one-phone-25-workers.md)). The PRD's minimums were set for tablets (Android 9 / API 28, iOS 15). We need a clear support policy that sales can quote, and an in-app check that warns about weak hardware (FR-PLT-04).

## Decision

### 1. Minimum supported

| | Android | iOS |
|---|---|---|
| OS | **Android 9 (API 28)** minimum (PRD FR-PLT-01); **Android 11+ recommended** and the only versions we certify | **iOS 15** minimum (PRD); certify on iOS 16+ |
| CPU / ABI | arm64-v8a (certified); armeabi-v7a built and best-effort | A12 Bionic or newer recommended (iPhone XS/XR and later) |
| RAM | ≥3 GB (warn below 4 GB) | Any supported iPhone |
| Front camera | ≥5 MP, ≥640×480 @ 15 fps in CameraX `ImageAnalysis` | Any |
| Storage free | ≥1 GB at install | ≥1 GB |
| Screen | ≥5.5" recommended, portrait | Any iPhone; iPad works via responsive layout (not certified) |

`targetSdk` follows Google Play's yearly requirement (API 35 for 2026 submissions; bump each August). The iOS deployment target is set to the higher of iOS 15 and the Flutter/LiteRT minimums at the time.

### 2. Reference ("certified") devices

At least **two Android** and **one iOS** reference devices, certified before GA (NFR-HW-01). They are chosen from the best-selling ₹8,000–₹12,000 phones in the launch clusters at M0 time. Candidate families: Redmi A-series / Redmi 13C-class, Samsung Galaxy A0x/M1x-class, Realme Narzo/C-series. iOS: iPhone SE (2nd/3rd gen) and iPhone 11 as the lowest certified.

Certification means passing on that exact model:
- pipeline p95 ≤700 ms; cold start ≤5 s;
- 12-hour soak and 4-hour battery tests ([ADR-0018](0018-power-thermal-and-reliability-on-a-phone.md));
- FAR/FRR/PAD targets in field-like lighting ([ADR-0020](0020-testing-strategy-and-ml-evaluation.md));
- kiosk (pinning / Guided Access) behaviour checked;
- the OEM battery-killer behaviour documented.

The certified list is published on the website and in the setup guide.

### 3. In-app hardware check (FR-PLT-04)

The setup wizard (design 06, "This device") runs:
1. OS version, RAM, free storage.
2. Front camera resolution and the frame rate actually achieved.
3. A 10-second **mini-benchmark** of detection + embedding on synthetic frames.
4. Whether a TTS voice is present for the chosen languages.

Result: **Ready / Works with limits / Not supported**. "Works with limits" explains the impact (e.g. "Recognition may take up to 2 s"). "Not supported" still allows a trial, with a clear warning.

### 4. Accessories (recommended, not required)

- A phone stand with height adjustment (eye level ~1.5 m from the floor), a 2 m charging cable and a 10 W+ charger.
- Optional USB LED light for dark gates (Risk R-2).

## Options considered

| Option | Verdict |
|---|---|
| Raise Android minimum to 11 | Considered. Kept at 9 per PRD for reach, but we certify only 11+. Revisit if crash rates on 9–10 are high. |
| Support Android Go edition (≤2 GB RAM) | Rejected: ML + camera headroom too thin. |
| Certify iPads now | Not a Phase 1 target. The layouts work, but there is no certification effort. |

## Consequences

- QA needs a device lab of ~6 phones: the reference models plus one Android 9 and one Android 10 for best-effort checks.
- Sales should steer new purchases to the certified list.
