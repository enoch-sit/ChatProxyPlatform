@echo off
setlocal EnableExtensions

set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%pre_installation_probe.ps1" %*
exit /b %ERRORLEVEL%
