@echo off
rem Runs SyncGate on an Android phone connected by USB (Windows).
rem Same options as android.ps1, e.g.:  android.cmd -Device R58M123ABC -Rotation 270
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0android.ps1" %*
exit /b %ERRORLEVEL%
