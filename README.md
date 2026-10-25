# SyncGate

A privacy-first, DPDP-ready, offline facial recognition attendance system designed for contract and blue-collar labor on budget Android devices.

One phone at the factory gate marks attendance by face, fully offline. Face templates never leave the phone. The same phone is the owner's admin console for enrolment, corrections, reports and payroll exports (Excel / Tally). The app is built in **Flutter** for **Android and iOS** from one codebase, with the camera and ML pipeline in native code.

| Document | What it covers |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Product requirements |
| [docs/adr/](docs/adr/README.md) | Architecture decisions (ADR-0001 … ADR-0022) |
| [docs/delivery/phase-1-delivery-plan.md](docs/delivery/phase-1-delivery-plan.md) | Milestones, sprints, epics and tasks |
| [docs/delivery/frontend-implementation-plan.md](docs/delivery/frontend-implementation-plan.md) | How the Flutter app is built, screen by screen |
| [docs/designs/](docs/designs) | Screen designs, iOS and Android (17 screens each) |

---

## Getting started

This section takes a new machine from nothing to running the app on an Android emulator or phone, and (on a Mac) an iPhone simulator or device.

> **Status:** the toolchain steps (1–5) work today. The app itself lands with the first frontend milestone ([plan](docs/delivery/frontend-implementation-plan.md), step F0). Until `apps/mobile/` exists, stop after step 5.

### What you can build where

| Your machine | Android | iOS |
|---|---|---|
| Windows | ✅ build, run, test | ❌ write code only. iOS builds need Xcode, which only runs on macOS |
| macOS | ✅ | ✅ |
| Linux | ✅ | ❌ |

Dart unit tests, widget tests and golden tests run on every OS, for both the iOS and the Android look of each screen.

### 1. Prerequisites

| Tool | Version | Needed for |
|---|---|---|
| Git | 2.40+ | Everything |
| Flutter SDK (includes Dart) | Stable channel, version pinned in `.fvmrc` | Everything |
| FVM (Flutter Version Management) | 3.x | Using the exact pinned Flutter version (recommended) |
| Melos | 8.x | Running commands across the monorepo |
| JDK | 17 (bundled with Android Studio) | Android builds |
| Android Studio + Android SDK | SDK Platform 35, Build-Tools 35, Platform-Tools, Emulator | Android builds and emulator |
| Xcode | 16+ (macOS only) | iOS builds and simulator |
| CocoaPods | 1.15+ (macOS only) | iOS native dependencies |
| VS Code or Android Studio | latest, with the Flutter + Dart plugins | Editing and debugging |

Disk space: about 15 GB (Flutter ~3 GB, Android SDK + one emulator image ~10 GB).

### 2. Install Flutter

**Option A — FVM (recommended; matches CI).** FVM installs the exact Flutter version this repo pins.

Windows (PowerShell):

```powershell
dart pub global activate fvm   # needs any Dart/Flutter already on PATH; otherwise use: choco install fvm
fvm install                     # run in the repo root; reads .fvmrc
fvm flutter --version
```

macOS:

```bash
brew tap leoafarias/fvm
brew install fvm
fvm install
fvm flutter --version
```

With FVM, prefix Flutter commands with `fvm` (for example `fvm flutter doctor`), or point your IDE at `.fvm/flutter_sdk`.

**Option B — plain Git install.** Use this if you don't want FVM.

Windows (PowerShell):

```powershell
git clone --depth 1 -b stable https://github.com/flutter/flutter.git C:\src\flutter
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\src\flutter\bin", "User")
# Open a NEW terminal so the PATH change applies, then:
flutter --version
```

macOS / Linux:

```bash
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/development/flutter
echo 'export PATH="$HOME/development/flutter/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc
source ~/.zshrc
flutter --version
```

The first `flutter` command downloads the Dart SDK and engine, which takes a few minutes.

**Windows only:** Flutter plugins need symlink support. Turn on Developer Mode (Settings → System → For developers → Developer Mode), or open the page directly:

```powershell
start ms-settings:developers
```

### 3. Set up Android

1. Install **Android Studio** from <https://developer.android.com/studio> (on Windows you can also run `winget install Google.AndroidStudio`).
2. Open Android Studio → **More Actions → SDK Manager**:
   - *SDK Platforms:* **Android 15 (API 35)**.
   - *SDK Tools:* **Android SDK Build-Tools 35**, **Android SDK Command-line Tools (latest)**, **Android SDK Platform-Tools**, **Android Emulator**.
3. Accept the Android SDK licences:

   ```bash
   flutter doctor --android-licenses
   ```

4. Create an emulator: **More Actions → Virtual Device Manager → Create device** → Pixel 7 → API 35 image. For the camera, set **Front camera: Webcam0** under *Advanced settings* so the emulator uses your laptop webcam.
5. Or use a real phone: enable **Developer options → USB debugging**, plug it in, and accept the prompt on the phone.

If `flutter doctor` can't find the SDK or JDK:

```bash
flutter config --android-sdk "<path to Android SDK>"
flutter config --jdk-dir "<Android Studio>/jbr"
```

### 4. Set up iOS (macOS only)

```bash
xcode-select --install                                  # command-line tools
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS                       # simulator runtime
brew install cocoapods
open -a Simulator
```

To run on a physical iPhone, open `apps/mobile/ios/Runner.xcworkspace` in Xcode once, choose your Apple ID team under **Signing & Capabilities**, and trust the developer certificate on the phone (Settings → General → VPN & Device Management).

### 5. Check the toolchain

```bash
flutter doctor -v
```

You need green ticks for **Flutter**, **Android toolchain** and (on a Mac) **Xcode**. The *Chrome*, *Visual Studio* and *Linux toolchain* lines are for web and desktop targets, which SyncGate doesn't use, so you can ignore them.

### 6. Get the code and dependencies

```bash
git clone git@github.com:Luffy610/SyncGate.git
cd SyncGate
dart pub global activate melos
melos bootstrap          # installs dependencies for every package and app
melos run gen            # runs code generation (Riverpod, freezed, l10n)
```

If `melos` isn't found, add the pub cache to your PATH: `%LOCALAPPDATA%\Pub\Cache\bin` on Windows, `$HOME/.pub-cache/bin` on macOS/Linux.

### 7. Run the app

The app has three flavours ([ADR-0021](docs/adr/0021-build-ci-cd-release-and-store-compliance.md)). Use **dev** for day-to-day work. It includes a fake camera feed and a debug panel, so you can test gate mode without real faces or ML models.

```bash
cd apps/mobile
flutter devices                                    # list emulators and phones
flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.json
```

| Flavour | Command | Use |
|---|---|---|
| dev | `flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.json` | Local development; fake camera; debug tools |
| staging | `flutter run --flavor staging -t lib/main_staging.dart --dart-define-from-file=env/staging.json` | QA and beta builds |
| prod | `flutter run --release --flavor prod -t lib/main_prod.dart --dart-define-from-file=env/prod.json` | Customer build; no debug features |

**Test the app without a camera (dev flavour):** open the debug panel (long-press the SyncGate logo on the gate screen) to fire scripted gate events: *match*, *not recognised*, *already marked*, *low light*. The setup wizard can be skipped with seeded demo data (24 workers, day and night shifts) from the same panel.

### 8. Run the tests

```bash
melos run analyze        # flutter analyze + import-boundary lint, all packages
melos run test           # unit + widget tests, all packages
melos run test:golden    # golden (screenshot) tests for iOS and Android looks
melos run golden:update  # regenerate goldens after an approved design change
```

For a single package: `cd packages/sg_ui && flutter test`.

### Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter: command not found` | Open a new terminal after changing PATH, or use `fvm flutter` |
| `Building with plugins requires symlink support` (Windows) | Turn on Developer Mode (step 2) |
| `Android license status unknown` | `flutter doctor --android-licenses` |
| `Unable to locate Android SDK` | `flutter config --android-sdk <path>` |
| `CocoaPods not installed` or pod errors | `brew install cocoapods`, then `cd apps/mobile/ios && pod install --repo-update` |
| Emulator shows a black camera | AVD settings → Front camera → Webcam0, or use the dev flavour's fake camera |
| Hindi or Tamil text shows boxes | Fonts are bundled in `packages/sg_ui/assets/fonts`; run `melos bootstrap` again |

---

## Repository layout

Target layout, from [ADR-0003](docs/adr/0003-app-architecture-and-repository-layout.md):

```
apps/mobile/          Flutter app (flavours dev | staging | prod)
apps/vision_bench/    ML benchmark app (internal)
packages/sg_domain/   Pure Dart domain: entities, shift engine, export builders
packages/sg_data/     Drift + SQLCipher database, repositories, backup codec
packages/sg_vision/   Native camera + ML plugin (Kotlin / Swift)
packages/sg_platform/ Kiosk, clock, thermal, TTS wrappers
packages/sg_ui/       Design tokens, adaptive components, fonts
packages/sg_l10n/     Translations (ARB) and voice-clip manifest
services/licence/     Go licence server
ml/                   Models, evaluation harness
docs/                 PRD, ADRs, delivery plans, designs
```
