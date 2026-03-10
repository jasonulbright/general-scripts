@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OSD-ComputerSetup.ps1"
if %ERRORLEVEL% NEQ 0 exit /b 1630
exit /b 0
