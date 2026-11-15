#!/usr/bin/env bash
# Runs SyncGate on an iPhone connected by USB. macOS only (needs Xcode).
# Usage: ./ios.sh [--help]
set -euo pipefail

PLATFORM_NAME="iOS"
# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
parse_args "$@"

[[ "$(uname -s)" == "Darwin" ]] || die "iOS builds need a Mac with Xcode. On Windows or Linux use the Android script."

step "Checking Xcode and CocoaPods"
command -v xcodebuild >/dev/null 2>&1 ||
  die "Xcode is not installed. Install it from the App Store, then run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
note "$(xcodebuild -version | head -1)"
command -v pod >/dev/null 2>&1 || die "CocoaPods is not installed. Run: brew install cocoapods"
note "CocoaPods $(pod --version)"

# A physical iPhone needs a signing team. Xcode writes it into the project
# the first time you pick one; until then the build cannot be signed.
PBXPROJ="$REPO_ROOT/apps/mobile/ios/Runner.xcodeproj/project.pbxproj"
if ! grep -q 'DEVELOPMENT_TEAM = ' "$PBXPROJ"; then
  step "One-time step: choose a signing team in Xcode"
  note "1. Xcode opens the project now."
  note "2. Select Runner (left) → target Runner → Signing & Capabilities."
  note "3. Tick 'Automatically manage signing' and pick your Apple ID team"
  note "   (Xcode → Settings → Accounts to add one; a free Apple ID works)."
  note "4. If the bundle ID is taken, change it to something unique, e.g. in.syncgate.app.<yourname>."
  note "5. Close Xcode and run this script again."
  open "$REPO_ROOT/apps/mobile/ios/Runner.xcworkspace" || true
  exit 1
fi

bootstrap

pick_device ios
build_run_args
# iOS flavour schemes are not set up yet, so no --flavor (README, Option B).
note "If the build stops at CocoaPods: cd apps/mobile/ios && pod install --repo-update"
note "First run on this iPhone: if it says 'Untrusted Developer', open"
note "Settings → General → VPN & Device Management, trust your certificate, and run again."
run_app
