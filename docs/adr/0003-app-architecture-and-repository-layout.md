# ADR-0003: Layered, modular app architecture and monorepo layout

- **Status:** In review
- **Proposed outcome:** Accepted
- **Date:** 24-10-2026
- **Deciders:** Engineering
- **Related:** PRD §8.2 · TC-01, TC-05 · ADR-0002, ADR-0004, ADR-0010, ADR-0011

## Context

The app has strict rules that should be enforced by structure rather than by discipline alone. The main ones:

- Biometric data never leaves the device (TC-01).
- Templates are only readable by the attendance feature (CMP-03).
- The data model must allow Phase 2 sync without a migration (TC-05).

We also need fast unit tests for the shift engine and exports, and a codebase several engineers can work in at once.

## Decision

### Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│ Presentation  (apps/mobile)                                          │
│  Gate │ Setup │ Admin: Today, Workers, Enrol, Exceptions, Reports,  │
│  Settings  — Flutter widgets, go_router, Riverpod providers          │
├──────────────────────────────────────────────────────────────────────┤
│ Application   (use cases)                                            │
│  MarkAttendance, EnrolWorker, CorrectRecord, ExportMonth,            │
│  CreateBackup, RestoreBackup, ActivateLicence, EraseWorker …         │
├──────────────────────────────────────────────────────────────────────┤
│ Domain        (packages/sg_domain — pure Dart, no Flutter imports)   │
│  Entities, value objects, ShiftEngine, DirectionResolver,            │
│  ExportBuilders (xlsx/Tally), LicenceVerifier, AuditChain            │
├──────────────────────────────────────────────────────────────────────┤
│ Data          (packages/sg_data)                                     │
│  Drift DB (SQLCipher), repositories, KeyManager, BackupCodec,        │
│  DriveClient, LicenceClient                                          │
├──────────────────────────────────────────────────────────────────────┤
│ Platform      (packages/sg_vision, sg_platform)                      │
│  Native camera + ML (Kotlin / Swift), TemplateVault, kiosk APIs,     │
│  monotonic clock, thermal state, TTS, device integrity               │
└──────────────────────────────────────────────────────────────────────┘
```

Dependency rule: each layer depends only on layers **below** it. `sg_domain` depends on nothing but `dart:core` and small pure packages (`collection`, `meta`). Lint rules enforce this (`import_lint` / custom `analysis_options.yaml`). CI fails on forbidden imports.

### The biometric boundary

- **Templates live only in the native `TemplateVault`** inside `sg_vision` ([ADR-0010](0010-local-storage-and-encryption.md)). Dart can ask the vault to `enrol(workerId, captureSessionId)`, `delete(workerId)`, `count(workerId)` and `startMatching()`. Dart can **never read an embedding vector**.
- Frames and crops never leave native memory ([ADR-0006](0006-on-device-vision-pipeline.md)).
- Consequence: no Dart code path — backup, export, logging, crash report — can serialise biometric data, because Dart never holds it.

### Repository layout (Melos monorepo)

```
syncgate/
├─ apps/
│  ├─ mobile/              Flutter app; flavours dev | staging | prod
│  └─ vision_bench/        M0 benchmark + field-test app (internal only)
├─ packages/
│  ├─ sg_domain/           pure Dart domain, shift engine, export builders
│  ├─ sg_data/             Drift schema, migrations, repositories, backup codec
│  ├─ sg_vision/           Flutter plugin: Kotlin (CameraX+LiteRT) / Swift (AVFoundation+LiteRT)
│  ├─ sg_platform/         kiosk, clock, thermal, integrity, TTS wrappers (Pigeon)
│  ├─ sg_ui/               design tokens, adaptive components, icons, fonts
│  └─ sg_l10n/             ARB files, generated localisations, voice-clip manifest
├─ services/
│  └─ licence/             Go licence server + migrations + OpenAPI
├─ ml/
│  ├─ models/              versioned .tflite files + model cards (checksums, licences)
│  ├─ eval/                Python evaluation harness (FAR/FRR, PAD, fairness)
│  └─ datasets/README.md   provenance and consent records (no data in git)
├─ tools/                  scripts (codegen, font subsetting, release)
└─ docs/
   ├─ PRD.md
   ├─ adr/                 this folder
   └─ designs/ios|android  exported screen designs
```

### App-level patterns

| Concern | Choice |
|---|---|
| State management | **Riverpod 2** with code generation (`riverpod_generator`). `AsyncNotifier` for use cases; providers scoped per mode. |
| Navigation | **go_router** with a top-level redirect driven by `AppModeController` (`setup` → `gate` ⇄ `admin`). See [ADR-0004](0004-single-device-gate-and-admin-modes.md). |
| Dependency injection | Riverpod providers only. No service locator. |
| Immutable models | `freezed` + `json_serializable` for DTOs; plain Dart classes in the domain. |
| Errors | Typed `Result`/sealed failure classes in the domain; never throw across layers for expected cases. |
| Concurrency | Heavy work (exports, backup encryption, Argon2id) runs in `Isolate.run`. The UI isolate stays at 60 fps. |
| Native interop | **Pigeon** for all channels. No hand-written `MethodChannel` strings. |
| Config | Compile-time flavours (`--dart-define-from-file`) for licence-server URL, Sentry DSN and build type. No runtime remote config in Phase 1. |

## Options considered

| Option | Verdict |
|---|---|
| Single package app | Rejected: the biometric boundary and the pure-domain rule would rest on convention only. |
| Bloc instead of Riverpod | Viable. Riverpod chosen for less boilerplate, compile-safe providers and easy overrides in tests. |
| GetX / service locator | Rejected: hidden global state, weak testability. |
| Separate repositories per package | Rejected: one small team; atomic changes across app and plugin matter more. |

## Consequences

- New features add a use case + domain logic + UI. Reviewers check the layer imports.
- The Go licence server lives in the same repo but is deployed independently.
- Melos scripts (`melos run test`, `melos run analyze`, `melos run gen`) are the standard entry points in CI.
