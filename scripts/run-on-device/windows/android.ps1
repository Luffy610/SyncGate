<#
.SYNOPSIS
  Runs SyncGate on an Android phone connected by USB (Windows).

.DESCRIPTION
  Builds the SyncGate dev app and runs it on an Android phone connected by
  USB, with the real camera and face-recognition models. iOS needs a Mac:
  use scripts/run-on-device/macos/ios.sh there.

  Run from PowerShell:      .\android.ps1 [options]
  or from Command Prompt:   android.cmd [options]

.PARAMETER Device
  Phone to use when several are connected (ID or name from `flutter devices`).
  Default: the first phone found.

.PARAMETER DebugBuild
  Debug build: hot reload works, but face recognition is several times slower.

.PARAMETER ProfileBuild
  Profile build: near-release speed, with DevTools.

.PARAMETER DemoCamera
  Use the scripted demo camera, not the real one.

.PARAMETER SetupWizard
  Start with the first-run setup wizard (default: straight to the gate,
  owner PIN 123456).

.PARAMETER Rotation
  Force the camera frame rotation: 0, 90, 180 or 270. Try 90 or 270 if
  faces are never found.

.PARAMETER NoBootstrap
  Skip 'melos bootstrap' and code generation (faster when nothing changed).

.EXAMPLE
  .\android.ps1
.EXAMPLE
  .\android.ps1 -Device R58M123ABC -Rotation 270
#>
[CmdletBinding()]
param(
  [string]$Device = '',
  [switch]$DebugBuild,
  [switch]$ProfileBuild,
  [switch]$DemoCamera,
  [switch]$SetupWizard,
  [ValidateSet('', '0', '90', '180', '270')]
  [string]$Rotation = '',
  [switch]$NoBootstrap
)

# Native commands are checked with $LASTEXITCODE. 'Continue' keeps Windows
# PowerShell 5.1 from treating their stderr notices as fatal errors.
$ErrorActionPreference = 'Continue'

function Write-Step([string]$Text) { Write-Host "`n==> $Text" -ForegroundColor Yellow }
function Write-Note([string]$Text) { Write-Host "    $Text" }
function Stop-WithError([string]$Text) {
  Write-Host "`nError: $Text" -ForegroundColor Red
  exit 1
}

# The repo root, from this file's location (scripts\run-on-device\windows).
$RepoRoot = (Resolve-Path -ErrorAction Stop (Join-Path $PSScriptRoot (Join-Path '..' (Join-Path '..' '..')))).Path

# ---- Flutter ---------------------------------------------------------------
Write-Step 'Checking Flutter'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Stop-WithError 'flutter is not on your PATH. Install Flutter (README: Windows setup), then open a new PowerShell window.'
}
Push-Location $RepoRoot
try {
  & dart run tools/device.dart check-flutter
} finally { Pop-Location }

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  Write-Note 'adb is not on your PATH; that is fine, Flutter finds it through the Android SDK.'
}

# ---- Packages --------------------------------------------------------------
if ($NoBootstrap) {
  Write-Step 'Skipping bootstrap (-NoBootstrap)'
} else {
  Write-Step 'Fetching packages and generating translations'
  $globals = (& dart pub global list) -join "`n"
  if ($globals -notmatch '(?m)^melos ') {
    Write-Note 'Installing Melos (one time)'
    & dart pub global activate melos | Out-Null
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'could not install Melos.' }
  }
  Push-Location $RepoRoot
  try {
    & dart pub global run melos bootstrap
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'melos bootstrap failed (see the messages above).' }
    & dart pub global run melos run gen
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'code generation failed (see the messages above).' }
  } finally { Pop-Location }
}

# ---- Device ----------------------------------------------------------------
Write-Step 'Looking for a connected Android phone'
$pickArgs = @('run', 'tools/device.dart', 'pick', 'android')
if ($Device) { $pickArgs += @('--device', $Device) }
Push-Location $RepoRoot
try {
  $deviceId = (& dart @pickArgs | Select-Object -Last 1)
  $pickExit = $LASTEXITCODE
} finally { Pop-Location }
if ($pickExit -ne 0 -or -not $deviceId) {
  Stop-WithError 'no Android phone to run on (see above), then run this script again.'
}
$deviceId = $deviceId.Trim()
Write-Note "Using device $deviceId"

# ---- Run -------------------------------------------------------------------
$mode = '--release'
if ($DebugBuild) { $mode = '--debug' }
if ($ProfileBuild) { $mode = '--profile' }

$runArgs = @(
  'run', $mode, '-d', $deviceId, '--flavor', 'dev',
  '-t', 'lib/main_dev.dart', '--dart-define-from-file=env/dev.json'
)
if (-not $DemoCamera) { $runArgs += '--dart-define=VISION=real' }
if (-not $SetupWizard) { $runArgs += '--dart-define=DEV_START=gate' }
if ($Rotation) { $runArgs += "--dart-define=CAMERA_ROTATION=$Rotation" }

Write-Step 'Building and installing (the first build takes several minutes)'
if ($DemoCamera) { Write-Note 'Camera: demo camera' } else { Write-Note 'Camera: real camera + face models' }
if ($SetupWizard) { Write-Note 'Start:  setup wizard' } else { Write-Note 'Start:  gate (admin PIN 123456)' }
if ($DebugBuild) { Write-Note 'Debug build: face recognition will be slow; use the default release build to judge speed.' }
Write-Note 'Press q in this window to stop the app.'

Push-Location (Join-Path (Join-Path $RepoRoot 'apps') 'mobile')
try {
  & flutter @runArgs
  exit $LASTEXITCODE
} finally { Pop-Location }
