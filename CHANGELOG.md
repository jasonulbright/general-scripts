# Changelog

All notable changes to General Scripts are documented in this file.

## [1.0.0] - 2026-03-10

### Added
- **ElevatedLauncher** — WinForms GUI for running applications under alternate credentials with saved target list and `Start-Process -Credential` execution
- **OSD-ComputerSetup** — WinPE hostname and OU selection GUI for MECM OSD task sequences, with batch launcher
- **Export-MECMCredential.ps1** — generates encrypted credential files for use during OSD
- **Remove-AppRegistryEntries.ps1** — cleans orphaned application registry entries from HKCR, HKLM, and HKCU with parameterized filtering
- **Set-MECMManagementPoint.ps1** — reconfigures MECM management point assignments
- **remove-appdeployments.ps1** — bulk removes application deployments from MECM
- **rename-extensions.ps1** — batch renames file extensions in a target directory

### Fixed
- HKCR filtering in Remove-AppRegistryEntries now applies all parameters against ProductName
- ElevatedLauncher verb corrected: `Refresh-ListView` renamed to `Update-ListView`
