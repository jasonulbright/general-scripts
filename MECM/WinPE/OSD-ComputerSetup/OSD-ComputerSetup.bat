@echo off
REM Prestart command wrapper for OSD-ComputerSetup.ps1
REM Configure this as the prestart command on boot media (Customization tab)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0OSD-ComputerSetup.ps1"
if %ERRORLEVEL% NEQ 0 exit /b 1630
exit /b 0
