<#
.SYNOPSIS
  Runs the whole stack test on an Android emulator or phone: a fresh Spring
  Boot API and database, then the real Flutter UI driving it over HTTP.

.DESCRIPTION
  1. stops any running SyncGate API and deletes its dev database (services/api/data)
  2. starts the API and waits until it is healthy
  3. runs apps/mobile/integration_test/real_stack_test.dart on the device
  4. stops the API again

  Needs: Java 17, Flutter, and a running emulator (or a phone with USB debugging).
  It deletes services/api/data, so do not run it if you want to keep that data.

.EXAMPLE
  powershell -File tools/test-real-stack.ps1
  powershell -File tools/test-real-stack.ps1 -Device emulator-5554
#>
param(
  [string]$Device = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$api = Join-Path $root 'services/api'
$app = Join-Path $root 'apps/mobile'

function Stop-Api {
  Get-CimInstance Win32_Process -Filter "Name='java.exe'" |
    Where-Object { $_.CommandLine -match 'SyncgateApi|spring-boot' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

if (-not $Device) {
  $line = (& adb devices) | Select-String 'device$' | Select-Object -First 1
  if (-not $line) { throw 'No device found. Start an emulator or connect a phone, then run again.' }
  $Device = ($line.ToString() -split '\s+')[0]
}
Write-Host "Using device $Device"

Stop-Api
Start-Sleep -Seconds 2
Remove-Item -Recurse -Force (Join-Path $api 'data') -ErrorAction SilentlyContinue

$log = Join-Path $env:TEMP 'syncgate-api-test.log'
# The Maven wrapper's .cmd launcher fails on some Windows setups (notably repos
# under a OneDrive-redirected Desktop), while the shell script from Git for
# Windows works everywhere, so prefer it and fall back to the .cmd.
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
  $server = Start-Process -FilePath $bash.Source -ArgumentList '-c', '"./mvnw -q spring-boot:run"' `
    -WorkingDirectory $api -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Hidden
} else {
  $server = Start-Process -FilePath cmd.exe -ArgumentList '/c', "`"$(Join-Path $api 'mvnw.cmd')`" -q spring-boot:run" `
    -WorkingDirectory $api -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -WindowStyle Hidden
}

try {
  Write-Host 'Waiting for the API...'
  $up = $false
  for ($i = 0; $i -lt 90 -and -not $up; $i++) {
    try { $up = (Invoke-RestMethod http://localhost:8080/actuator/health -TimeoutSec 2).status -eq 'UP' } catch { Start-Sleep -Seconds 2 }
  }
  if (-not $up) { throw "The API did not start. See $log" }

  Push-Location $app
  & flutter test integration_test/real_stack_test.dart -d $Device --flavor dev --dart-define-from-file=env/dev.json
  $code = $LASTEXITCODE
  Pop-Location
  exit $code
}
finally {
  Stop-Api
  if ($server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }
}
