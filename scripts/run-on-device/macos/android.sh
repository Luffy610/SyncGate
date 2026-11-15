#!/usr/bin/env bash
# Runs SyncGate on an Android phone connected by USB.
# macOS (also works on Linux). Usage: ./android.sh [--help]
set -euo pipefail

PLATFORM_NAME="Android"
# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
parse_args "$@"

check_flutter
if ! command -v adb >/dev/null 2>&1; then
  note "adb is not on your PATH; that is fine, Flutter finds it through the Android SDK."
fi
bootstrap
pick_device android
build_run_args
RUN_ARGS+=(--flavor dev)
run_app
