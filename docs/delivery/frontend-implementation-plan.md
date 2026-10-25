# SyncGate — Frontend Implementation Plan (Flutter, iOS + Android)

| Field | Value |
|---|---|
| Status | Draft v0.1, for review |
| Date | 25-10-2026 |
| Branch | `feature/mobile-app-frontend` |
| Scope | The Flutter app (`apps/mobile`) and its UI packages (`sg_ui`, `sg_l10n`), plus the Dart contracts the UI needs from `sg_domain` / `sg_vision` / `sg_platform` |
| Sources | [PRD](../PRD.md) · ADR [0001](../adr/0001-phase-1-scope-one-phone-25-workers.md), [0003](../adr/0003-app-architecture-and-repository-layout.md), [0004](../adr/0004-single-device-gate-and-admin-modes.md), [0005](../adr/0005-design-system-and-platform-adaptive-ui.md), [0008](../adr/0008-enrolment-and-template-management.md), [0011](../adr/0011-data-model-append-only-events.md), [0013](../adr/0013-backup-restore-and-device-replacement.md), [0014](../adr/0014-licensing-and-licence-server.md), [0015](../adr/0015-reports-and-payroll-export.md), [0016](../adr/0016-localization-voice-and-indian-formats.md), [0020](../adr/0020-testing-strategy-and-ml-evaluation.md), [0021](../adr/0021-build-ci-cd-release-and-store-compliance.md) · [Delivery plan](phase-1-delivery-plan.md) · [Designs](../designs) |

---

## 1. Goal and approach

Build every Phase 1 screen in [`docs/designs`](../designs) **once in Flutter**. Each screen renders with **Cupertino chrome on iOS** and **Material 3 chrome on Android**, and the **brand look is the same on both** ([ADR-0005](../adr/0005-design-system-and-platform-adaptive-ui.md)).

The frontend must not wait for the native vision pipeline, the encrypted database or the licence server. So:

1. **Contracts first.** The UI talks only to Dart interfaces: repositories in `sg_domain`, `GateVisionService` in `sg_vision`, `KioskService` and friends in `sg_platform`.
2. **Fakes behind every contract.** The `dev` flavour wires in-memory repositories seeded with demo data (the 24 workers in the designs) and a **scripted fake camera**. Every screen can be built, demoed and golden-tested before the real implementations exist.
3. **Swap in real implementations** as the other epics land (Drift + SQLCipher in E10/E11, native vision in E06–E09, licence client in E14). Each swap is one Riverpod provider override and needs no screen changes.

**Done** for the frontend means: all 17 designed screens plus the undesigned screens in §9 work on both platforms against the real back ends, and meet the Definition of Done in the delivery plan §7 (goldens on both platforms, English + Hindi, audit entries for admin actions).

---

## 2. Monorepo scaffold (F0)

### 2.1 Layout

```
SyncGate/
├─ .fvmrc                      # pinned Flutter stable version
├─ pubspec.yaml                # Dart pub workspace root + melos config
├─ analysis_options.yaml       # shared lints (very_good_analysis base + custom rules)
├─ apps/
│  └─ mobile/
│     ├─ lib/
│     │  ├─ main_dev.dart        # overrides providers with fakes + debug panel
│     │  ├─ main_staging.dart
│     │  ├─ main_prod.dart       # never imports src/dev/
│     │  ├─ bootstrap.dart       # shared startup: error zones, ProviderScope, runApp
│     │  └─ src/
│     │     ├─ app/              # SyncGateApp, router, AppModeController, theme wiring
│     │     ├─ application/      # use cases (MarkAttendance, EnrolWorker, CorrectRecord …)
│     │     ├─ features/
│     │     │  ├─ gate/          # designs 01–04
│     │     │  ├─ setup/         # designs 05–08 + first shift, owner PIN, first worker
│     │     │  ├─ unlock/        # design 09
│     │     │  ├─ today/         # design 10
│     │     │  ├─ workers/       # designs 11–14, worker profile
│     │     │  ├─ exceptions/    # design 15
│     │     │  ├─ reports/       # design 16
│     │     │  └─ settings/      # design 17 + settings hub, shifts, users, Tally mapping
│     │     └─ dev/              # fakes, seed data, debug panel (dev flavour only)
│     ├─ env/{dev,staging,prod}.json
│     ├─ android/  ios/
│     └─ test/  integration_test/
└─ packages/
   ├─ sg_ui/          # tokens, themes, adaptive components, icons, fonts
   ├─ sg_l10n/        # ARB files + generated AppLocalizations + voice-clip manifest
   ├─ sg_domain/      # pure Dart: entities, value objects, repository interfaces, Result types
   ├─ sg_vision/      # plugin; F0 ships only the Dart API + Pigeon contract (native in E06)
   └─ sg_platform/    # plugin; F0 ships only the Dart API (kiosk, clock, thermal, TTS)
```

`sg_data` is created by the data epic (E10/E11). The frontend depends only on the interfaces in `sg_domain`.

### 2.2 Tooling

| Item | Decision |
|---|---|
| Flutter | Latest stable at scaffold time, pinned in `.fvmrc`, committed |
| Workspace | Dart **pub workspaces** (`workspace:` in the root `pubspec.yaml`) + **Melos 8** scripts (config under `melos:` in the root `pubspec.yaml`) |
| Melos scripts | `analyze`, `test`, `test:golden`, `golden:update`, `gen` (build_runner + gen-l10n), `format:check` (names are used in the [README](../../README.md)) |
| Lints | `very_good_analysis` + `import_lint` rules: `sg_domain` may not import Flutter; `features/*` may not import `dev/`; screens may not import `package:flutter/cupertino.dart` or raw Material widgets (enforced by a custom lint over `features/`) |
| Code gen | `riverpod_generator`, `freezed`, `json_serializable`, `go_router_builder` (typed routes), `flutter gen-l10n` |
| Platforms | `flutter create --platforms=android,ios --org in.syncgate --project-name syncgate apps/mobile` |
| Min OS | Android `minSdk 28`, `targetSdk 35`; iOS deployment target 15.0 ([ADR-0019](../adr/0019-supported-devices-and-os-versions.md)) |
| Orientation | Portrait only in Phase 1 (ADR-0001). Tablets get the same layout with `maxWidth: 600` centred. |

### 2.3 Flavours

| Flavour | Android `applicationId` | iOS bundle ID | Entry point | Extras |
|---|---|---|---|---|
| dev | `in.syncgate.app.dev` | `in.syncgate.app.dev` | `main_dev.dart` | Fake repos, fake camera, debug panel, seeded demo data |
| staging | `in.syncgate.app.staging` | `in.syncgate.app.staging` | `main_staging.dart` | Real implementations, staging licence server |
| prod | `in.syncgate.app` | `in.syncgate.app` | `main_prod.dart` | Real implementations; debug code is not imported, so it is tree-shaken out |

- Android: `productFlavors` in `android/app/build.gradle.kts`, with an app-name suffix ("SyncGate Dev").
- iOS: three schemes plus `Debug-dev`, `Release-dev`, … build configurations, with xcconfig files per flavour. **Setting up the iOS schemes needs Xcode, so it must be done on a Mac.** Until then, the iOS project builds the default scheme only.
- `env/<flavour>.json` → `--dart-define-from-file`: `LICENCE_BASE_URL`, `SENTRY_DSN` (empty in dev), `BUILD_FLAVOUR`.

### 2.4 Core dependencies (apps/mobile and sg_ui)

| Package | Use |
|---|---|
| `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator` | State and dependency injection (ADR-0003) |
| `go_router`, `go_router_builder` | Navigation, mode redirect, typed routes |
| `freezed`, `json_serializable` | UI state classes and DTOs |
| `flutter_localizations`, `intl` | gen-l10n, Indian formats (`en_IN`, `hi_IN`) |
| `wakelock_plus` | Keep the screen on in Gate mode |
| `just_audio` | Pre-recorded voice clips and earcons |
| `flutter_tts` | Worker names in the gate voice prompt |
| `local_auth` | Face ID / fingerprint admin unlock (E04-T03) |
| `share_plus` | Export and backup sharing |
| `device_info_plus`, `package_info_plus` | "This device" check, About screen |
| `mobile_scanner` | "Scan QR on invoice" on the licence step (confirm ML Kit's size cost at M0) |
| `uuid` | UUIDv7 IDs in fakes (the real IDs come from the data layer) |
| Dev: `alchemist`, `mocktail`, `patrol` | Goldens, mocks, device integration tests (ADR-0020) |

Open decision **FE-1:** ADR-0003 names Riverpod 2. Riverpod 3 is the current stable line and works the same way with code generation. Proposal: start on Riverpod 3 and amend ADR-0003 in the F0 PR.

---

## 3. Architecture inside the app

### 3.1 App modes and routing (ADR-0004)

`AppModeController` (a Riverpod `Notifier<AppMode>`) is the single source of truth: `setup | gate | admin(role)`. The mode is stored in the database (in a key-value table in fakes) so it survives restarts.

```
/setup/language → /setup/licence → /setup/shift → /setup/camera → /setup/kiosk → /setup/owner → /setup/first-worker
/gate                 (scanning / matched / not recognised / cooldown are states, not routes)
/gate/manual          (guard pick-from-list)
/unlock               (PIN pad, modal over gate)
/admin/today          ┐
/admin/workers        │ StatefulShellRoute: one branch per tab, each tab keeps its own stack
/admin/reports        │
/admin/settings       ┘
/admin/workers/new             → /details → /notice → /face   (full-screen flow, hides tabs)
/admin/workers/:id
/admin/exceptions
/admin/settings/backup         (design 17)
/admin/settings/shifts, /users, /tally, /language, /privacy, /about
```

**Redirect rules** in `GoRouter.redirect`, driven by `AppModeController`:

| Current mode | Allowed routes | Anything else goes to |
|---|---|---|
| setup | `/setup/*` | the current setup step |
| gate | `/gate`, `/gate/manual`, `/unlock` | `/gate` |
| admin(owner/admin) | `/admin/*` | `/admin/today` |
| admin(gate operator) | `/admin/today` (limited), `/gate/manual` | `/admin/today` |

Role guards for screens and actions follow the ADR-0004 §2 table. They are implemented once, as `can(Capability)` on the current session, and used both by the router and to hide or disable buttons.

**Auto-return to Gate:**
- `IdleWatcher` wraps the admin shell in a `Listener` that resets a timer on every pointer event. On timeout (2 min, configurable 1–10 min) it sets the mode to gate.
- `AppLifecycleListener`: when the app resumes from the background in admin mode, the mode goes back to gate.
- The enrolment face-capture screen holds the timer (`IdleWatcher.hold()` / `release()`).
- The banner "Gate is paused — workers can't mark attendance · Back to gate" is pinned to the top of the admin shell.

### 3.2 Layers and providers

```
Screen (ConsumerWidget, sg_ui components only)
  └─ watches  → ScreenController (AsyncNotifier, per feature, holds UI state)
                  └─ calls → UseCase (application/, plain Dart class, Provider)
                               └─ uses → Repository / Service interfaces (sg_domain, sg_vision, sg_platform)
                                            └─ bound in main_*.dart → Fake* (dev) or real implementation
```

- Interfaces needed by the UI, with fakes in `apps/mobile/lib/src/dev/fakes/`:
  - `WorkerRepository`, `AttendanceRepository`, `ExceptionRepository`, `ShiftRepository`, `UserRepository`, `ConsentRepository`, `AuditLog`, `SettingsRepository`, `BackupService`, `ExportService`, `LicenceService`.
  - From `sg_vision`: `GateVisionService`, `EnrolmentCaptureService`, `CameraCheckService`.
  - From `sg_platform`: `KioskService`, `ClockService`, `VoiceService`, `DeviceCheckService`.
- Expected failures are returned as `Result<T, Failure>` (sealed classes), not thrown (ADR-0003). The UI maps each `Failure` to a localised message.
- **Biometric boundary:** no interface the UI can see carries an image or an embedding. The camera preview is a `textureId` (an int), and vision results are small events. This holds in the fakes too.

### 3.3 Vision contract the UI is built against

The contract mirrors the Pigeon v0 events in E02-T02. The frontend owns its Dart shape; the native team implements it.

```dart
abstract interface class GateVisionService {
  Future<int> start(GateVisionConfig config);   // returns textureId for Texture(...)
  Future<void> stop();
  Stream<VisionEvent> get events;
}

sealed class VisionEvent {}
class FaceSeen      extends VisionEvent { final double faceSizeRatio; }
class QualityHint   extends VisionEvent { final QualityIssue issue; }  // tooDark, backlight, tooFar, turnLess, blurry, covered, dirtyLens
class Match         extends VisionEvent { final String workerId; final double score, margin, liveness; }
class NoMatch       extends VisionEvent { final NoMatchReason reason; }  // unknown, lowMargin, livenessFail
class PipelineStats extends VisionEvent { final double fps; final int p95Ms; final double lux; }
```

The **fake** shows the grey silhouette from the designs instead of a texture. It emits scripted sequences, triggered from the debug panel or on a timer ("demo loop").

---

## 4. Design system: `sg_ui` (F1)

### 4.1 Tokens (`sg_ui/lib/src/tokens.dart`)

Values come from ADR-0005 §2 and from the designs. They are mirrored exactly; a token change is a design review item.

| Group | Tokens |
|---|---|
| Colour, light | `ink #15171A`, `groundIos #F2F1ED`, `groundAndroid #F7F6F2`, `surface #FFFFFF`, `line #E6E4DD`, `muted #5E615F`, `brandYellow #FFC21A`, `brandYellowTint` (selected row / chip fill, ≈ `#FFF3CC`, take the exact value from the canvas) |
| Colour, gate (dark) | `gateBg #101214`, `gatePanel #16191C`, `gateCard` (list rows ≈ `#1C1F23`), `gateText #FFFFFF`, `gateMuted` (≈ `#9AA0A6`) |
| Status | `successFill #0E7A45`, `successText #0B7A43`, `successOnDark` (the bright green "IN" ≈ `#3DDC84`), `danger #A8261C`, `warningBg #FDF0D2`, `warningText #6B4100`/`#7A4A00`, `warningIcon #B26A00`, `infoBg #E7ECF8`, `infoText #1F3F8F` |
| Radius | card: iOS 12 / Android 16; chip: iOS 18 / Android 8; button: iOS 12 / Android 24 (pill); gate panel 28; sheet top 28 |
| Spacing | 4-pt scale: `s1 4`, `s2 8`, `s3 12`, `s4 16`, `s5 20`, `s6 24`, `s8 32`; screen gutter 16 (Android) / 20 (iOS) |
| Sizes | button height iOS 50 / Android 48; min touch 48; nav bar iOS 83 / Android 80; avatar 48 (lists), 56 (gate) |
| Motion | `fast 150ms`, `normal 250ms`; gate confirm hold `1500ms`; not-recognised auto-retry `3000ms` |

Values marked ≈ were read from the PNG exports. Confirm them against the canvas source (<https://claude.ai/artifact/8pZEg6Qb8Hkv3hZj1QG5nK>) before freezing.

### 4.2 Typography and fonts (E05-T03)

- Bundle in `sg_ui/assets/fonts/`, all SIL OFL 1.1, with `OFL.txt` committed next to them: IBM Plex Sans (400/500/600/700), IBM Plex Sans Devanagari (400/500/600/700), Noto Sans Gujarati / Tamil / Gurmukhi (500/600), IBM Plex Mono (500/600).
- `fontFamily: 'IBMPlexSans'` with `fontFamilyFallback: ['IBMPlexSansDevanagari', 'NotoSansGujarati', 'NotoSansTamil', 'NotoSansGurmukhi']`, so mixed strings such as "Continue · आगे बढ़ें" render correctly.
- Subset the Latin fonts with `tools/fonts/subset.sh` (pyftsubset). Keep the regional fonts whole. Budget: ≤6 MB.
- `SgText` styles: `gatePrompt` 44/600 (Hindi first line) + 30/400 (English line), `gateName` 38/700, `gateClock` 56 mono, `titleLarge` 34/700 (iOS large title), `titleAndroid` 28/600, `title` 22/600, `body` 16/400, `bodyStrong` 16/600, `label` 13/600 caps (+0.6 letter spacing, used by "NOT MARKED YET · 6"), `caption` 13/400, `mono` for IDs, times and licence keys.
- `google_fonts` is **not** used, because the app must work offline.

### 4.3 Themes

- `SgTheme.light(platform)` → `ThemeData` (Material 3, custom `ColorScheme` from tokens) **plus** `CupertinoThemeData`, with an `SgTokens` `ThemeExtension` that carries everything that isn't in `ThemeData`.
- `SgTheme.gate()` → the dark theme for gate screens and face capture.
- The platform comes from `Theme.of(context).platform`. The debug panel can override it, so you can see the iOS look on an Android device and the other way round.

### 4.4 Adaptive components

Screens use only these. Each one switches on the platform internally.

| Component | iOS rendering | Android rendering | Seen in |
|---|---|---|---|
| `SgScaffold` | `CupertinoPageScaffold`-like, ground `#F2F1ED` | `Scaffold`, ground `#F7F6F2` | all |
| `SgTopBar` | Large title on tab roots; centred 17 pt title on pushed screens; text actions ("‹ Back", "Cancel", "Next") | Small top app bar, left-aligned 22 sp title, icon actions (←, ✕, ⋮) | 10–17 |
| `SgNavBar` | Tab bar 83 pt, hairline top border, filled active icon tinted yellow | M3 Navigation bar 80 dp, yellow **pill** active indicator | 10, 11, 16, 17 |
| `SgPrimaryAction` | "+" in the top bar | Extended FAB "Enrol worker" | 10, 11 |
| `SgButton` (primary / secondary / outline / text / danger / onColor) | Radius 12, height 50 | Pill, height 48 | all |
| `SgTextField` | Grouped inset row: label left, value right | Outlined field with floating label | 06, 12 |
| `SgSelectField` | Row with value + chevron → pushes a picker list | Outlined dropdown → modal bottom sheet list | 12 |
| `SgDateField` | Row → `CupertinoDatePicker` sheet | Outlined field → `showDatePicker`; shows DD-MM-YYYY | 12 |
| `SgSection` | Grouped inset section with caps header | Card with caps label above | 12, 17 |
| `SgSwitch` | iOS switch 51×31, green track | M3 switch 52×32, ink track, yellow thumb with ✓ | 07, 17 |
| `SgSegmented` | Segmented control, white thumb | Segmented buttons, yellow fill + ✓ | 09, 16 |
| `SgChoiceChips` (filter) | Pill chips, selected = ink fill, white text | Chips radius 8, selected = yellow tint + ✓ | 10, 11, 15, 16 |
| `SgSelectRow` (radio / list choice) | Checkmark on the selected row | Radio button; selected card gets yellow tint + ink border | 05, 16 |
| `SgSheet` | Sheet with grabber, Cancel / Title / Save in the header | Modal bottom sheet with drag handle, actions at the bottom | 15 |
| `SgListRow` / `SgCardList` | Inset grouped list | Card list with dividers | 11, 17 |
| `SgStatCard` | Same on both: dot + label, big number, caption | | 10 |
| `SgBanner` (warning / info / success / danger) | Same on both, with icon (never colour only) | | 07, 10, 14, 17 |
| `SgStepper` (wizard bar) | Segmented progress bar "Step n of 6" | | 05–08 |
| `SgFlowSteps` (1 Details — 2 Notice — 3 Face) | Same on both | | 12–14 |
| `SgAvatarInitials` | Same; initials only, never a photo (ADR-0005 §4) | | 01–04, 11, 15 |
| `SgStatusTag` (MISSING OUT / MANUAL / CLOCK …) | Same | | 15 |
| `SgPinPad` + `SgPinDots` | Round keys | Pill keys | 09 |
| `SgBiometricGlyph` | Face ID glyph, "Use Face ID" | Fingerprint glyph, "Use fingerprint" | 09 |
| `SgShareIcon` | Square + up arrow | Three connected nodes | 16 |
| `SgIcon` set | Stroke icons from the designs, exported to an icon font or SVGs (E05-T04) | | all |
| Gate-only: `GateHeader`, `ScanFrame` (yellow corner brackets), `GateResultPanel` (green / red / grey), `GateFooter` (clock, shift, progress, last mark) | Same on both platforms | | 01–04 |
| Capture-only: `CaptureRing` (progress arc, yellow head + green done segments), `AngleTile` (Front / Left / Right / Mask) | Same on both | | 14 |

Every component gets a widgetbook-style **catalogue page** in the dev flavour (`/dev/catalogue`) and golden tests in 2 platforms × 2 locales (`en`, `hi`) × 2 text scales (1.0, 1.3).

---

## 5. Localisation and voice: `sg_l10n` (F1, alongside the design system)

- ARB files: `app_en.arb` (template), `app_hi.arb` at M1. `gu`, `ta`, `pa`, `mr` are added per cluster, with no code change.
- Key naming: `<feature>_<screen>_<element>`, e.g. `gate_scan_promptPrimary`. Plurals use ICU (`{count, plural, …}`).
- **Bilingual gate copy:** gate screens show the **device language first and English second** (e.g. "स्क्रीन की ओर देखें / Look at the screen · no need to touch"). `GateCopy` looks up the same key in two locales (`lookupAppLocalizations(Locale)`), without a second set of keys.
- Three language settings (ADR-0016): device language (gate + default), admin-user language, worker language (that worker's greeting, voice and notice). The language chip on the gate header ("हिन्दी") switches the device language for the gate.
- Formats in `sg_l10n/lib/formats.dart`: `formatDate` → `DD-MM-YYYY`, `formatTime` (12 h with AM/PM by default, 24 h toggle), `formatNumber` with Indian grouping, Western digits by default.
- Voice: `VoiceService` (in `sg_platform`, faked in dev) with `playPhrase(Phrase, Locale)`, using pre-loaded Opus clips listed in `sg_l10n/voice/manifest.json`, and `speakName(String, Locale)` via TTS. Earcons: rising tone for success, low double tone for failure.
- Legal notice text (design 13) is versioned content, not ordinary UI strings: `sg_l10n/notices/<version>/<locale>.md` plus a recorded clip.

---

## 6. Screen-by-screen specification

Design file numbers refer to `docs/designs/{ios,android}/NN-*.png`. The **Data** column lists what each screen reads, all through the interfaces in §3.2.

### 6.1 Gate mode (designs 01–04): `features/gate`

Gate mode is **one route** with a state machine, so transitions don't re-run route animations or rebuild the camera texture.

```
GateState = scanning | matched(worker, direction, time, onTime) | notRecognised(hint, retryIn)
          | cooldown(worker, lastMarkTime) | paused(reason)        // admin open, licence restricted, camera error
```

| # | Screen | Layout and behaviour | Data |
|---|---|---|---|
| 01 | **Scanning** | `GateHeader` (logo, "SyncGate", "● Offline · saved on this phone", language chip, lock button). Camera panel (radius 28) with "● Liveness check on" pill and yellow `ScanFrame`. Bilingual prompt. `GateFooter`: big mono clock, shift name + window, date, "18 of 24 marked IN · 6 not yet", yellow progress bar, last-mark row (avatar, name, ID · dept, IN + time). | `GateVisionService.events`, `ShiftRepository.current()`, `AttendanceRepository.watchToday()` |
| 02 | **Matched** | The panel turns `successFill` with a white ✓ circle, a white pill "IN · 05:52 AM", the name (38/700), the greeting in the worker's language ("स्वागत है, रमेश"), "W-0112 · Weaving · on time", and a voice caption. The footer increments the count and highlights the last-mark row in a green tint. Holds for 1.5 s, then returns to scanning. Plays the earcon + phrase + TTS name. **The event is written before the confirmation shows** (NFR-REL-02). | `MarkAttendance` use case → `AttendanceRepository.append()` |
| 03 | **Not recognised** | The panel turns `danger` with a ✕ circle, "पहचान नहीं हुई / Not recognised", a hint built from the last `QualityHint` ("Take off the helmet or come a little closer…"), a countdown "Trying again in 3 s", a white "Try again" button and an outline "Guard: pick worker from list" button. Auto-retries after 3 s. | `NoMatch` + last `QualityHint` |
| — | **Cooldown** (no design yet) | Neutral grey panel: "Already marked IN at 05:52". Nothing is stored (FR-ATT-05). **Needs a design**, see §9. | `AttendanceRepository.lastEvent(worker)` |
| 04 | **Manual entry** | Title "Manual entry", "Guard G-02 · tap the worker at the gate", yellow "⚑ Flagged in reports" tag, search field, "NOT MARKED YET · 6" list (only workers not yet marked for the current direction, sorted by name, selected row = yellow border + ✓), required reason chips (Not recognised · Mask / helmet · Injury · Camera issue · New worker not enrolled), footer with "Cancel" and "Save IN · Ramesh". The save button is disabled until a worker and a reason are chosen. Shows an error at 3 manual entries per worker per day. No PIN needed; logged as the gate operator. | `WorkerRepository.notMarked(direction)`, `MarkManualAttendance` |

Other gate behaviour:
- **Wake lock** on while in gate mode. **Dim** the screen after N seconds with no `FaceSeen`, and wake it on the next face (ADR-0018). The brightness control goes through `sg_platform`.
- **Kiosk warnings:** "Not pinned" (Android) / "Guided Access is off" (iOS) badge in the header when `KioskService.state` is not locked.
- **Owner-only badges** after unlock, e.g. backup overdue for 14+ days.
- **Debug panel** (dev flavour only): long-press the logo → buttons for Match (random / chosen worker), NoMatch, Cooldown, each QualityHint, licence states, and a platform-look toggle.

### 6.2 Setup wizard (designs 05–08 + undesigned steps): `features/setup`

`SetupController` holds the wizard draft and persists each completed step, so a crash resumes at the right step. "Step n of 6" + `SgStepper`. Android back is "←"; iOS back is "‹ Back".

| Step | Screen | Content | Notes |
|---|---|---|---|
| 1 | **Choose a language** (05) | Bilingual title, explainer, 6 language rows (native script + English + cluster, e.g. "ગુજરાતી · Gujarati · Surat"), "Continue · आगे बढ़ें". | Selecting a row switches the app locale live. Languages without an ARB yet are shown but marked "coming soon" (decision FE-3). |
| 2 | **Activate your licence** (06) | Mono licence-key field with `SGT-XXXX-XXXX-XXXX` auto-format, "Scan QR on invoice", "THIS DEVICE" card (front camera MP, memory, OS → Ready / Works with limits / Not supported), offline reassurance, "Activate", "No key yet? Start 30-day free trial". | `LicenceService.activate()` / `startTrial()`; `DeviceCheckService`. Activation needs internet; show an offline error state with "Start trial instead". |
| 3 | **First shift** (no design yet) | Shift name, start and end time (crosses midnight allowed), grace minutes, weekly off. Defaults: "Day 06:00–14:00", grace 10 min. | **Needs a design** (E05-T05 lists "first-shift setup"). |
| 4 | **Check camera & light** (07) | Live preview with a dashed oval, "● Live preview" pill, light chip ("Light low · 42 lux"). Check card: Light (bar + advice), Backlight, Lens, Face size. "Screen fill light" switch. "Check again" + "Continue". | `CameraCheckService` (fake returns scripted readings). Continue is allowed with warnings. |
| 5 | **Pin SyncGate to the screen** (08) | Illustration, "HOW TO" + "App pinning off" status tag, 3 numbered steps, "Pin SyncGate now", "Open Settings". iOS variant: Guided Access steps (triple-click), "Open Settings › Accessibility". | `KioskService.startPinning()` / `.state`; `KioskService.openSettings()`. |
| 6 | **Owner PIN + first worker** (no design yet) | (a) Create a 6-digit owner PIN, confirm it, show the **recovery code once** with a "I've written it down" check. (b) "Enrol your first worker" → enrolment flow (§6.4), or "Later". | **Needs a design.** The owner PIN is not in FR-ADM-04's list, but ADR-0004 requires it and the recovery code at setup. |
| — | **Restore from backup** (entry from step 1 or 2) | Pick a file or Google Drive → passphrase → integrity check → licence transfer → done, with workers marked "Needs face". | **Needs a design** (E05-T05 "restore"). M2. |

### 6.3 Admin unlock (design 09): `features/unlock`

- Android: ✕ close at top left. iOS: "Back to gate" text button.
- Logo, "Admin access", "Enter your 6-digit PIN", **role segmented control** (Owner / Admin / Gate operator), 6 PIN dots, keypad (1–9, biometric glyph, 0, backspace), "Use fingerprint" / "Use Face ID" link, footer "Gate operators can fix gate issues but can't see reports or export data."
- Behaviour: auto-submit at 6 digits; dots shake + haptic on a wrong PIN; lockout after 5 tries with an exponential back-off countdown (up to 15 min). Biometric unlock only if enabled for that user (`local_auth`). On success → `AppModeController.enterAdmin(role)`, and an audit entry is written.
- Data: `UserRepository.verifyPin()`. Argon2id hashing lives in the data layer; the fake compares plain strings in dev only.

### 6.4 Admin shell, Today and Workers (designs 10–14)

**Admin shell:** `StatefulShellRoute` with 4 tabs (Today, Workers, Reports, Settings), `SgNavBar`, and the "Gate is paused" banner. **Note:** the banner is in ADR-0004 but doesn't appear in designs 10–17, so its placement needs design confirmation (§9).

| # | Screen | Content | Data |
|---|---|---|---|
| 10 | **Today** | Title + "Sat, 24-10-2026 · 10:42 AM" (Android: search + ⋮; iOS: "+" for Enrol). Dark shift card: "Day shift is running", window · expected count, "● Offline OK", yellow "Start gate mode" button. Shift chips (All / Day / Night). 2×2 stat cards: Present (of expected), Absent (on leave), Late (after grace time), On premises (went OUT). "N records need review" card → Exceptions. Backup-overdue warning card with "Back up". Android FAB "Enrol worker". | `TodaySummary` from `AttendanceRepository` + shift engine; `ExceptionRepository.openCounts()`; `BackupService.lastBackup()` |
| 11 | **Workers** | Title, search, chips "All 25 / Not in 6 / ● Needs face 1", list rows: avatar initials, name, "W-0125 · Stitching · Day", status on the right ("Needs face" amber, "IN 05:51" green, "Not in" muted). FAB / "+". Tapping a row opens the worker profile (§9). | `WorkerRepository.watchAll()` joined with today's status |
| 12 | **New worker · Details** | `SgFlowSteps` 1/3. Android: ✕ + title + "Next" pill button; iOS: Cancel / New worker / Next. Fields: Full name, Worker ID (mono, auto `W-0101…`, "Auto-assigned. You can change it."), Date of birth (DD-MM-YYYY, live "✓ Age 28 — must be 18 or older to enrol" or red block), Department (picker + "add new"), Designation, Shift group, Contractor (optional), Phone (optional, +91), Language (+ "Notices and voice prompts for this worker use this language."). iOS groups them as WORKER / WORK / CONTACT & LANGUAGE. | `WorkerRepository.nextCode()`, `isCodeUnique()`; DOB check blocks under-18s (CMP-10) |
| 13 | **Privacy notice** | Steps 1 ✓ / 2 / 3. "Show to **Sunita Devi** in her language" + "🔊 सुनाएँ" (Read aloud). A scrollable notice card in the worker's language with sections (what is kept and why / where / your rights / grievance). A big consent checkbox row, bilingual. Footer note on what is saved, with the legal basis placeholder `[CONSENT OR LEGITIMATE USE — TBD]` (TBD-L1). "Agree & capture face" is disabled until the box is ticked. | `ConsentRepository.record()`; notice content from `sg_l10n/notices`; `VoiceService` |
| 14 | **Face capture** | Dark. ✕ + worker name + "Step 3 of 3". Preview panel with a quality banner ("Too dark — move closer to the light"), `CaptureRing`, bilingual instruction ("Slowly turn your head right"), 4 `AngleTile`s (Front / Left / Right done/now/pending; Mask optional), privacy note ("Photos are deleted once the face code is made…"), "Skip mask sample". When all angles are done: the duplicate check, then success → back to Workers with a snackbar. Duplicate found → dialog "This face looks like **Ramesh Kumar (W-0112)**" → Cancel / Override with reason. | `EnrolmentCaptureService` (start, per-angle progress events, finish → `EnrolResult.ok / duplicate(workerId)`); holds the idle timer |

### 6.5 Exceptions (design 15): `features/exceptions`

- Back to Today (iOS shows "‹ Today" + large title). Chips: "All 4 / Manual 2 / Missing OUT 1 / …" with counts.
- Cards: `SgStatusTag` (MISSING OUT amber, MANUAL blue, CLOCK red, plus LOW MARGIN, DUPLICATE, SPOOF SUSPECT, LIVENESS ACTIVE), date/time on the right (mono), "Name · ID", detail line.
- Tap → **Correct record** `SgSheet`: avatar, name · ID, date · shift · department; two time tiles (IN · FACE, OUT · NEW); the editable tile opens a time picker; required reason dropdown (preset reasons + "Other…"); an **audit preview** line ("Audit log will record: OUT none → 14:05, by Owner, 24-10-2026 10:48…"). Android: Cancel / "Save correction" at the bottom; iOS: Cancel / Correct record / Save in the header.
- Clock exceptions open an info sheet listing the affected events, with "Mark reviewed".
- Data: `ExceptionRepository.watch(filter)`, `CorrectRecord` use case (writes a correction + audit entry and resolves the exception).

### 6.6 Reports (design 16): `features/reports`

- Title + ⋮ (column templates, Tally mapping). Segmented "Daily / Monthly muster".
- Filter chips row, horizontally scrollable: Month ("Oct 2026"), Dept, Shift, Contractor. Each opens a picker sheet.
- Summary card: "24 workers · 21 working days · See all", table with columns WORKER, P, A, LATE, OT H (mono numbers, ⚑ next to workers with open exceptions). "See all" → full-screen muster grid (per day P / A / HD / L / WO) with a frozen name column and horizontal scroll.
- "EXPORT FOR PAYROLL": select rows for Excel (.xlsx, "Template: Payroll — default columns") and Tally Prime (XML, "23 of 24 matched to Tally employees · 1 to map" in amber → mapping screen). "Export & share" button with the platform share icon.
- Before exporting: if open exceptions exist, a confirm dialog ("2 records still need review — they'll be marked ⚑"). Then a progress dialog (the export runs in an isolate) → OS share sheet. Gate operators never see this tab. Export is never blocked by licence state.
- Daily view: date picker + a list of IN, OUT, hours, status, flags per worker.
- Data: `ReportService.monthly(filter)`, `ExportService.excel()` / `.tally()` → file path → `share_plus`.

### 6.7 Settings and Backup & device (design 17): `features/settings`

- **Settings hub** (no design yet, §9): Backup & device · Shifts & rules · Users & PINs · Language · Tally mapping · Gate settings (auto-return time, cooldown, voice volume, quiet hours, screen fill light) · Privacy & DPDP pack · Diagnostics · About.
- **Backup & device** (17): warning hero "Last backup 8 days ago", date + destination, "Back up now". BACKUP section: "Auto backup to Google Drive" switch (account · when online), "Save backup file" (share sheet), "Remind me after: 7 days". Privacy note ("Backups never include face codes…"). LICENCE & DEVICE: Licence status + expiry, "Move to a new phone", "Report phone lost or stolen" (danger text).
- First backup → **set passphrase** flow: suggest 4 words, confirm, "We cannot recover it" acknowledgement. **Needs a design.**
- Role gating: backup, restore, move phone, licence, users = owner only.

### 6.8 Cross-cutting states

| State | Where | UI |
|---|---|---|
| Licence trial / check-in overdue / grace / restricted / revoked (ADR-0014 §2) | Today header, Settings, gate | `SgBanner` with the ADR's copy. Restricted: gate keeps working for 7 more days with a countdown, then a `paused` gate state. Export and backup are never disabled. |
| Camera permission denied | Gate, camera check, face capture | Rationale screen before the system prompt (store compliance), and a "Open Settings" recovery state |
| Thermal throttling / low battery | Gate | Small header chip, from `sg_platform` thermal events (ADR-0018) |
| Clock changed | Gate (owner badge), Today, Exceptions | CLOCK exception card |
| Empty states | Workers (no workers), Exceptions ("All clear"), Reports (no data for the month) | Illustration + one action |
| Loading / error | All `AsyncValue`s | Skeletons for lists; inline error with Retry; never a blank screen |

---

## 7. Implementation sequence

Each step is one or more PRs into `feature/mobile-app-frontend`, which is merged to `master` at the end of each milestone. Task IDs refer to the [delivery plan](phase-1-delivery-plan.md) §4.

| Step | Sprint | Deliverable | Delivery-plan tasks | Exit check |
|---|---|---|---|---|
| **F0 — Scaffold** | Pre-S1 / S1 | Workspace, `.fvmrc`, Melos scripts, lints, `apps/mobile` created for Android + iOS, 3 flavours (Android complete; iOS schemes need a Mac), `bootstrap.dart`, empty packages, CI `pr.yml` (analyze + test) | E03-T01, E03-T02, E03-T04 | `melos run analyze` and `melos run test` green; `flutter run --flavor dev` shows a placeholder screen on an Android emulator |
| **F1 — Design system** | S1–S3 | Tokens, fonts + fallback chain, light/gate themes, all components in §4.4, dev catalogue, goldens (2 platforms × en/hi × 2 text scales), Indian-script golden test | E05-T01, E05-T02, E05-T03, E02-T07, E05-T06 (baseline) | Catalogue matches the designs side by side; script goldens pass (M0-4) |
| **F2 — App shell** | S2–S3 | Domain interfaces + `Result`, fakes + seed data (the 24 workers, Day/Night shifts from the designs), `AppModeController`, router + redirects, admin shell, idle auto-return, paused banner, role guards, debug panel | E03-T03, E03-T05, E04-T01, E04-T04 | Mode transitions covered by widget tests; auto-return works; gate operator can't reach Reports |
| **F3 — Gate mode** | S3–S4 | Designs 01–04 + cooldown, gate state machine, fake vision scripts, voice service (fake → real clips), wake lock / dim | E04-T10, E04-T08 | The M0 demo works on the fake: walk-up → green → back to scanning in ≤3 s; manual entry flagged |
| **F4 — Setup + unlock** | S4–S5 | Designs 05–09 + first shift, owner PIN / recovery code, first worker; `local_auth` | E04-T02 (UI), E04-T03 | Fresh install → wizard → gate on both looks |
| **F5 — Admin screens** | S5–S7 | Designs 10–17: Today, Workers, enrolment flow (details, notice, capture), worker profile, Exceptions + correction sheet, Reports + export UI, Settings hub, Backup & device | E05 screens; E08, E12, E15 UI parts | Every designed screen has goldens on both platforms in en + hi |
| **F6 — Integrate real back ends** | S6–S8 | Swap fakes → Drift/SQLCipher repositories, native `sg_vision`, `sg_platform` kiosk/clock/TTS, licence client, Excel builder, backup codec. Patrol integration tests on device. | E10/E11 integration, E06–E09 integration, E14, E15 | M1 exit: friendly factory build (staging flavour) on one Android phone, iOS verified on a lab iPhone |
| **F7 — Beta and GA polish** | S9–S12 | Restore flow, Drive backup, Tally mapping, gu/ta then pa/mr locales, DPDP pack screens, design QA fixes, store screenshots | E13, E15, E16, E05-T07..T09 | Design QA passes; goldens in all shipped locales |

The dates align with the delivery plan: F0–F3 fit M0, where "foundations started early" includes `sg_ui`, l10n and the app shell. F4–F6 is M1. F7 is M2–M3.

---

## 8. Testing (ADR-0020, applied to the frontend)

| Level | What | Tooling | When |
|---|---|---|---|
| Unit | Controllers, use cases, gate state machine, formatters, PIN lockout timing, idle watcher | `flutter_test`, `mocktail`, `fake_async` | Every PR |
| Widget | Each screen against fakes: states, validation (DOB under 18, unique worker ID, required reasons), role gating, redirects | `flutter_test` + `ProviderScope` overrides | Every PR |
| Golden | Every `sg_ui` component and every screen: **iOS + Android** × `en` + `hi` (+ longest locale once added) × 1.0 / 1.3 text scale | `alchemist` (CI goldens with fonts loaded) | Every PR; updates need design approval |
| Accessibility | Tap targets ≥48, contrast (`meetsGuideline`), semantics labels on icon buttons, status never colour-only | `flutter_test` guidelines | Every PR |
| Integration | Wizard → gate → match (fake feed) → unlock → correct → export → share sheet; permission dialogs | `patrol` on emulator (dev) and the device lab (staging) | Nightly |
| Manual | Side-by-side comparison with the design PNGs on a real Android phone and a real iPhone | Checklist per screen | End of each F-step |

Golden tests run on Linux CI, so both platform looks are verified without a Mac. Real iOS builds and runs still need macOS (a CI runner or a lab Mac).

---

## 9. Gaps, open questions and decisions needed

| ID | Item | Needed by | Owner |
|---|---|---|---|
| FE-1 | Riverpod 3 instead of 2 (amend ADR-0003) | F0 | TL |
| FE-2 | **Mac access** for iOS schemes, signing, simulator and device runs. Development happens on Windows today. | F0 (schemes), F3 (first iOS run) | Eng lead |
| FE-3 | Show not-yet-translated languages in step 1 as "coming soon", or hide them? | F4 | Product |
| D-1 | **Missing designs:** setup step 3 (first shift), setup step 6 (owner PIN + recovery code + first worker), gate cooldown state, "Gate is paused" admin banner, Settings hub, Shifts & rules, Users & PINs, worker profile (deactivate / re-enrol / delete / data summary), backup passphrase, restore, Tally mapping, licence states, camera-permission rationale, duplicate-face dialog, empty states. E05-T05 covers some of these. | Before the matching F-step | Design |
| D-2 | Exact hex values marked ≈ in §4.1 (yellow tint, gate card, gate muted, bright green) | F1 | Design |
| D-3 | Icon set export format (icon font vs SVG + `flutter_svg`) | F1 | Design + FE |
| L-1 | Legal basis text on the notice (TBD-L1), and the notice copy per language | F5 (placeholder until then) | Legal |
| P-1 | Does "Scan QR on invoice" use `mobile_scanner` (adds ML Kit, ~2–3 MB) or the native `sg_vision` camera? | F4 | TL + AND/IOS |

---

## 10. Definition of done (frontend additions to the delivery plan §7)

- Uses only `sg_ui` components; no raw `Cupertino*` or Material widgets in `features/`.
- Matches the design on **both** platforms (golden + manual side-by-side check).
- All strings in ARB, with `en` and `hi` present; dates DD-MM-YYYY; works at 1.3× text scale without truncating.
- Works offline; no network call on any gate path.
- No image, frame or embedding crosses into Dart or appears in logs.
- Admin actions call a use case that writes an audit entry.
- Role gating tested for Owner, Admin and Gate operator.
