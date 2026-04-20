@echo off
REM client-check launcher
REM Runs client-check.ps1 next to this .cmd file and opens the report in Edge.
setlocal
set "PS1=%~dp0client-check.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
endlocal
