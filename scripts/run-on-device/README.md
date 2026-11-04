# Run on your phone (USB)

One command builds the SyncGate dev app and runs it on a phone plugged into your computer, with the **real camera and face-recognition models** and the demo data.

| Your computer | Android phone | iPhone |
|---|---|---|
| **macOS** | `macos/android.sh` | `macos/ios.sh` |
| **Windows** | `windows\android.cmd` (or `android.ps1`) | Not possible: iOS builds need a Mac with Xcode |
| **Linux** | `macos/android.sh` works too | Not possible |

```
scripts/run-on-device/
├── macos/
│   ├── android.sh     Android phone, from a Mac (or Linux)
│   ├── ios.sh         iPhone, from a Mac
│   └── _common.sh     shared by the two (not run directly)
└── windows/
    ├── android.ps1    Android phone, from Windows (PowerShell)
    └── android.cmd    the same, for Command Prompt or double-click
```

Each script:

1. checks Flutter (and Xcode/CocoaPods for iOS) and warns if Flutter isn't the pinned version;
2. installs Melos if needed, then runs `melos bootstrap` and `melos run gen`;
3. finds the connected phone, and tells you what to fix if it isn't ready;
4. runs `flutter run --release` on it, starting at the gate (owner PIN **123456**) with the real camera.

Device detection is shared by both OSes: `tools/device.dart`, which reads `flutter devices --machine`.

## Before the first run

You need the toolchain from the main [README](../../README.md#step-by-step-setup): Flutter 3.47.8, plus Android Studio's SDK (Android) or Xcode 16+ and CocoaPods (iOS).

**Android phone**

1. *Settings → About phone →* tap **Build number** seven times.
2. *Settings → Developer options →* turn on **USB debugging**.
3. Plug the phone in with a data cable, unlock it, and tap **Allow** on "Allow USB debugging?".

**iPhone** (Mac only)

1. Plug it in, unlock it and tap **Trust This Computer**.
2. iOS 16 or later: *Settings → Privacy & Security → Developer Mode →* on, then restart the phone.
3. The first time, `ios.sh` opens Xcode so you can choose a signing team: *Runner → Signing & Capabilities →* tick **Automatically manage signing** and pick your Apple ID (a free one works). If Xcode says the bundle ID is taken, change it to something unique such as `in.syncgate.app.yourname`. Close Xcode and run the script again.
4. After the first install, if the phone says **Untrusted Developer**: *Settings → General → VPN & Device Management →* trust your certificate, then run the script again.

With a free Apple ID, the app stops opening after 7 days; run the script again to reinstall it.

## Run it

**macOS**, from the repo root:

```bash
scripts/run-on-device/macos/android.sh     # Android phone
scripts/run-on-device/macos/ios.sh         # iPhone
```

**Windows**, from the repo root. In Command Prompt or by double-clicking:

```bat
scripts\run-on-device\windows\android.cmd
```

or in PowerShell:

```powershell
.\scripts\run-on-device\windows\android.ps1
```

The `.cmd` file runs the PowerShell script with `-ExecutionPolicy Bypass`, so you don't need to change your execution policy.

The first build takes several minutes; later ones are much faster. Press **q** in the terminal to stop the app.

## Options

| macOS (`.sh`) | Windows (`.ps1` / `.cmd`) | What it does |
|---|---|---|
| `-d`, `--device <id or name>` | `-Device <id or name>` | Pick the phone when several are connected (names and IDs: `flutter devices`). |
| `--debug` | `-DebugBuild` | Debug build: hot reload (`r`) works, but face recognition is several times slower. |
| `--profile` | `-ProfileBuild` | Near-release speed, with Flutter DevTools. |
| `--demo-camera` | `-DemoCamera` | Scripted demo camera instead of the real one. |
| `--setup-wizard` | `-SetupWizard` | Start with the first-run setup wizard instead of the gate. |
| `--rotation <0\|90\|180\|270>` | `-Rotation <0\|90\|180\|270>` | Force the camera frame rotation (see below). |
| `--no-bootstrap` | `-NoBootstrap` | Skip `melos bootstrap` and code generation when nothing changed. |
| `-h`, `--help` | `Get-Help .\android.ps1 -Detailed` | Show the options. |

Example: `scripts/run-on-device/macos/android.sh --device "Pixel 7" --rotation 270`

## Try face recognition

1. On the gate, tap the lock → PIN **123456** → **Workers → Enrol worker**.
2. Fill in the details, accept the notice, then follow the capture: look straight, turn left, turn right, then **Skip mask sample** (scroll down if you don't see it).
3. **Back to gate**, then look at the camera. You should see the green panel with your name and **IN · time**.
4. Ask someone who isn't enrolled to try: **Not recognised**.

Things to know:

- The demo workers have no real face codes, so only people you enrol will match.
- Face codes are kept in memory for now, so they are lost when the app restarts.
- There is no anti-spoofing yet (ADR-0007): a photo of an enrolled face will also match.

## If something goes wrong

| What you see | Try |
|---|---|
| "No Android phone found" | USB debugging on, the phone unlocked, the "Allow USB debugging" prompt accepted, a data cable. `adb devices` should list it. |
| iPhone "connected but not ready" | Unlock it, tap **Trust**, turn on Developer Mode, and check it appears in Xcode → *Window → Devices and Simulators*. |
| Signing / provisioning errors (iOS) | Pick a team in Xcode (see above); make the bundle ID unique. |
| CocoaPods errors (iOS) | `cd apps/mobile/ios && pod install --repo-update`, then run the script again. |
| Preview sideways, or the capture ring never moves | The phone reports its camera rotation wrongly. Run again with `--rotation 270` (Windows: `-Rotation 270`), then `90` if that doesn't help. Please tell us the phone model. |
| Recognition feels slow | Make sure you didn't pass `--debug`; the default release build is much faster. |
| Anything else | `flutter doctor -v`, and the [Troubleshooting](../../README.md#troubleshooting) table. |
