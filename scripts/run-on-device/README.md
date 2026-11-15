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
4. runs `flutter run --release` on it, starting at the gate (owner PIN **123456**) with the real camera and **live diagnostics** over the camera preview.

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
| `--rotation <0\|90\|180\|270>` | `-Rotation <0\|90\|180\|270>` | Force the camera frame rotation. Rarely needed: the app works the orientation out from the first few faces it sees. |
| `--no-diagnostics` | `-NoDiagnostics` | Hide the live numbers over the camera preview (on by default; see below). |
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

## Reading the diagnostics

While the real camera runs, a small strip over the preview shows what the face pipeline sees, and the same text is printed in the terminal once a second on lines starting `[sg_vision]`. It contains numbers and worker IDs only, never images. Example at the gate:

```
gate 480x640 fix 0° 9.8 fps 61 ms
face 0.93 size 9.1% yaw +0.08 roll -2° luma 121 sharp 180 ok
best w-new-100 0.71 (need 0.48) lead 0.52 (need 0.08)
gallery 1 · last: MATCH w-new-100
```

| Part | Meaning | Healthy |
|---|---|---|
| `480x640` | Frame size after rotation | Taller than wide when the phone is upright |
| `fix 0°` | Extra turn the app applied because the camera's reported orientation was wrong; `(calibrating)` for the first few faces after the camera starts | Any value, as long as it stops changing |
| `fps`, `ms` | Frames analysed per second; time per frame | 5 fps or more; under 200 ms |
| `face 0.93` | Detector confidence (`no face` when nothing is found) | 0.8 or more |
| `size` | Distance between the eyes as a share of the frame | 4.5 % or more (else "come closer") |
| `yaw`, `roll` | Head turn left/right (0 = straight, ±1 = side-on) and tilt in degrees | Near 0 when you look straight |
| `luma`, `sharp` | Face brightness (0–255) and sharpness | 40 or more; 20 or more |
| last word | `ok`, or why the frame was not used: `tooDark`, `backlight`, `tooFar`, `turnLess`, `blurry` | `ok` |
| `best … (need …)` | Closest enrolled worker, the score, and the score needed | Your score well above the need; a stranger's below it |
| `lead … (need …)` | Gap to the second-closest worker (`n/a` with one worker enrolled) | Above the need |
| `gallery`, `last` | Workers who can match now; the last decision | |

During enrolment the last line reads `capture front 2/3`: the step being captured and how many good frames it has. If a step does not advance, watch `yaw`: the front step wants it between −0.4 and +0.4, and each side wants it beyond ±0.35 (left and right in opposite directions).

**If recognition looks wrong, send us the `[sg_vision]` lines** from the terminal (copy a dozen from when it went wrong) and the phone model. That is enough to tell a camera problem from a matching problem.

## If something goes wrong

| What you see | Try |
|---|---|
| "No Android phone found" | USB debugging on, the phone unlocked, the "Allow USB debugging" prompt accepted, a data cable. `adb devices` should list it. |
| iPhone "connected but not ready" | Unlock it, tap **Trust**, turn on Developer Mode, and check it appears in Xcode → *Window → Devices and Simulators*. |
| Signing / provisioning errors (iOS) | Pick a team in Xcode (see above); make the bundle ID unique. |
| CocoaPods errors (iOS) | `cd apps/mobile/ios && pod install --repo-update`, then run the script again. |
| Faces rarely found, people not recognised | Look at the diagnostics. `fix` should settle after the first few faces and `roll` should be near 0° when you look straight. If `roll` stays near ±90° or `no face` shows while you face the camera, run again with `--rotation 90` (then `270`, `180`; Windows: `-Rotation`) and tell us the phone model and the `[sg_vision]` lines. |
| A capture step never completes | Watch `yaw` and the `capture …` line in the diagnostics (see above); turn your head further, slowly, and keep it there for a second. |
| Recognition feels slow | Make sure you didn't pass `--debug`; the default release build is much faster. |
| Anything else | `flutter doctor -v`, and the [Troubleshooting](../../README.md#troubleshooting) table. |
