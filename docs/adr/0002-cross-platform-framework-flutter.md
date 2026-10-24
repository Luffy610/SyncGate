# ADR-0002: Flutter for the app UI, with native camera and ML modules

- **Status:** Proposed — confirm at the end of the M0 feasibility spike (decision D-2)
- **Date:** 24-10-2026
- **Deciders:** Engineering, ML
- **Related:** PRD §8.1 TC-02, TC-03 · FR-PLT-01..03 · D-2 · ADR-0003, ADR-0006

## Context

We need **one product on Android and iOS** with all P0 features on both (FR-PLT-01). The app has two very different halves:

1. **A real-time vision loop.** Camera frames → detection → quality → liveness → embedding → match, at 10–15 fps, on budget Android hardware (TC-02). This must be native or close to it.
2. **A large amount of ordinary app UI.** Setup wizard, enrolment forms, consent notices in several scripts, dashboards, tables, exports, settings. The design ([ADR-0005](0005-design-system-and-platform-adaptive-ui.md)) is brand-driven: custom cards, chips and full-screen confirmations rather than stock platform widgets.

The team is small. We want one UI codebase, predictable rendering of Indian scripts on cheap phones, and a clean seam to native code for the camera and ML.

## Decision

- Build the app in **Flutter** (Dart 3, stable channel, latest stable at project start, pinned via FVM).
- Keep the **camera and the whole vision pipeline native**, inside a first-party Flutter plugin `sg_vision`:
  - **Android:** Kotlin, **CameraX** (`ImageAnalysis` with `STRATEGY_KEEP_ONLY_LATEST`), LiteRT.
  - **iOS:** Swift, **AVFoundation** (`AVCaptureVideoDataOutput`, `alwaysDiscardsLateVideoFrames`), LiteRT.
- Camera preview reaches Flutter through the **`Texture` registry**: zero-copy on both platforms, with no per-frame pixel transfer over the channel.
- **Frames never cross into Dart.** Dart receives only small **events** (`FaceSeen`, `QualityHint`, `Match{workerId, score, liveness}`, `NoMatch`, `PipelineStats`) over a **Pigeon**-generated, type-safe channel.
- Business logic (shift engine, exports, backups, licence verification) lives in **pure Dart packages**, so it is identical on both platforms and unit-testable on a laptop.

### M0 exit criteria that confirm this ADR

| Check | Target |
|---|---|
| Detection + liveness + embedding + match, p95 | ≤700 ms on each reference phone ([ADR-0019](0019-supported-devices-and-os-versions.md)) |
| Preview frame rate while pipeline runs | ≥24 fps preview, ≥10 fps analysed |
| Cold start to gate mode | ≤5 s |
| Install size (arm64 APK / iOS thin) | ≤80 MB |
| Devanagari, Gujarati, Tamil, Gurmukhi shaping | Correct conjuncts and matras in golden tests |
| 4-hour battery run in gate mode | Completes without thermal throttling below target |

If Flutter misses any of these and the cause is the Flutter layer (not the native pipeline), we fall back to **Option B** below.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A. Flutter + native vision plugin (chosen)** | One UI codebase; consistent pixel-level rendering on both OSs; strong text shaping (HarfBuzz) for Indian scripts; good performance on low-end Android; Texture-based preview; mature Pigeon codegen; Material 3 and Cupertino widget sets both available | Vision code is still written twice (Kotlin + Swift); app size baseline ~+8–10 MB for the engine; iOS look comes from Cupertino widgets, not native UIKit |
| B. React Native (New Architecture) + VisionCamera frame processors | Excellent camera library with JSI frame processors; large ecosystem; native UI components | Frame processors in worklets add complexity for a multi-stage pipeline; more variance across Android OEMs; JS bundle and Hermes tuning on low-end phones |
| C. Kotlin Multiplatform + Compose Multiplatform | Shared Kotlin logic; native Android; Compose on iOS is stable | Smaller iOS ecosystem; iOS team must still write Swift for camera; fewer ready plugins (Drive, share, TTS) |
| D. Two native apps (Kotlin + Swift) | Best per-platform fidelity and performance | Doubles UI work for a small team; feature drift between platforms |

## Consequences

**Positive**
- About 85% of the code (UI, domain, data, exports, l10n) is shared.
- The privacy boundary is clear: image data exists only inside native code and memory. Dart code cannot accidentally write a frame to disk or logs.
- Domain logic is testable without devices.

**Negative**
- Vision engineers maintain two native implementations (Kotlin, Swift). We keep them aligned with a shared **pipeline spec**, shared model files, and a **cross-platform parity test**: the same recorded frame sequences must give the same decisions on both.
- iOS screens use Cupertino widgets plus our own components. They feel native but are not UIKit. This is acceptable for this product.

## Follow-ups

- M0: build the benchmark app (`apps/vision_bench`) that runs the pipeline on recorded and live frames and reports per-stage latency.
- Record the D-2 outcome by updating this ADR to **Accepted**, or superseding it.
