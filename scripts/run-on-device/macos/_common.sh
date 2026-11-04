# Shared by android.sh and ios.sh. Not meant to be run on its own.
# shellcheck shell=bash

# ---- Options ---------------------------------------------------------------

DEVICE=""
BUILD_MODE="--release"
REAL_CAMERA=1
START_AT_GATE=1
ROTATION=""
BOOTSTRAP=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Builds the SyncGate dev app and runs it on an $PLATFORM_NAME phone connected by
USB, with the real camera and face-recognition models.

Options:
  -d, --device <id|name>  Phone to use when several are connected
                          (default: the first phone found).
      --debug             Debug build: hot reload works, but face
                          recognition is several times slower.
      --profile           Profile build: near-release speed, with DevTools.
      --demo-camera       Use the scripted demo camera, not the real one.
      --setup-wizard      Start with the first-run setup wizard
                          (default: straight to the gate, owner PIN 123456).
      --rotation <deg>    Force the camera frame rotation: 0, 90, 180 or 270.
                          Try 90 or 270 if faces are never found.
      --no-bootstrap      Skip 'melos bootstrap' and code generation
                          (faster when nothing changed since the last run).
  -h, --help              Show this help.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d | --device)
        [[ $# -ge 2 ]] || die "--device needs a value"
        DEVICE="$2"
        shift 2
        ;;
      --debug) BUILD_MODE="--debug"; shift ;;
      --profile) BUILD_MODE="--profile"; shift ;;
      --demo-camera) REAL_CAMERA=0; shift ;;
      --setup-wizard) START_AT_GATE=0; shift ;;
      --rotation)
        [[ $# -ge 2 ]] || die "--rotation needs a value"
        case "$2" in 0 | 90 | 180 | 270) ROTATION="$2" ;; *) die "--rotation must be 0, 90, 180 or 270" ;; esac
        shift 2
        ;;
      --no-bootstrap) BOOTSTRAP=0; shift ;;
      -h | --help) usage; exit 0 ;;
      *) usage >&2; die "unknown option: $1" ;;
    esac
  done
}

# ---- Output ----------------------------------------------------------------

step() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() {
  printf '\n\033[1;31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

# ---- Steps -----------------------------------------------------------------

# The repo root, from this file's location (scripts/run-on-device/macos).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

check_flutter() {
  step "Checking Flutter"
  command -v flutter >/dev/null 2>&1 ||
    die "flutter is not on your PATH. Install Flutter (README: Step-by-step setup), then open a new terminal."
  (cd "$REPO_ROOT" && dart run tools/device.dart check-flutter)
}

bootstrap() {
  [[ $BOOTSTRAP -eq 1 ]] || { step "Skipping bootstrap (--no-bootstrap)"; return; }
  step "Fetching packages and generating translations"
  if ! dart pub global list 2>/dev/null | grep -q '^melos '; then
    note "Installing Melos (one time)"
    dart pub global activate melos >/dev/null
  fi
  (cd "$REPO_ROOT" && dart pub global run melos bootstrap && dart pub global run melos run gen) ||
    die "bootstrap failed (see the messages above)."
}

# Prints the device ID for $1 (android|ios), or exits with advice.
pick_device() {
  step "Looking for a connected $PLATFORM_NAME phone"
  local args=(pick "$1")
  [[ -n $DEVICE ]] && args+=(--device "$DEVICE")
  local id
  if ! id="$(cd "$REPO_ROOT" && dart run tools/device.dart "${args[@]}")"; then
    die "no $PLATFORM_NAME phone to run on (see above), then run this script again."
  fi
  DEVICE_ID="$id"
  note "Using device $DEVICE_ID"
}

# Builds the `flutter run` arguments shared by both platforms into RUN_ARGS.
build_run_args() {
  RUN_ARGS=(run "$BUILD_MODE" -d "$DEVICE_ID" -t lib/main_dev.dart --dart-define-from-file=env/dev.json)
  [[ $REAL_CAMERA -eq 1 ]] && RUN_ARGS+=(--dart-define=VISION=real)
  [[ $START_AT_GATE -eq 1 ]] && RUN_ARGS+=(--dart-define=DEV_START=gate)
  [[ -n $ROTATION ]] && RUN_ARGS+=("--dart-define=CAMERA_ROTATION=$ROTATION")
  return 0
}

run_app() {
  step "Building and installing (the first build takes several minutes)"
  note "Camera: $([[ $REAL_CAMERA -eq 1 ]] && echo 'real camera + face models' || echo 'demo camera')"
  note "Start:  $([[ $START_AT_GATE -eq 1 ]] && echo 'gate (admin PIN 123456)' || echo 'setup wizard')"
  [[ $BUILD_MODE == "--debug" ]] && note "Debug build: face recognition will be slow; use the default release build to judge speed."
  note "Press q in this window to stop the app."
  cd "$REPO_ROOT/apps/mobile" || die "cannot find apps/mobile"
  exec flutter "${RUN_ARGS[@]}"
}
