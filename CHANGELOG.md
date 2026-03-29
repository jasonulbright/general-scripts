# Changelog

All notable changes to General Scripts are documented in this file.

## [1.0.6] - 2026-03-29

### Added
- **HyperV/Watch-VMLog.ps1** -- tail a log file inside a Hyper-V VM via PowerShell Direct with color-coded ERROR/WARNING output
- **HyperV/Get-VMLogInventory.ps1** -- discover running processes and log files across common paths inside a Hyper-V VM
- **Drivers/Remove-DriverStoreEntries.ps1** -- remove stubborn drivers from the Windows driver store by regex pattern with FileRepository cleanup and -WhatIf support
- **Filesystem/ConvertTo-Icon.ps1** -- convert PNG/JPG/BMP to multi-size .ico (256/48/32/16px), supports CLI and drag-and-drop GUI

## [1.0.2] - 2026-03-24

### Added
- **rename-extensions.ps1**: `-Archive` switch that creates a `.zip` of the target folder after renaming extensions. Streamlines the rename-zip-email workflow into a single command.
- **MECM/cachebaseline/**: Automated CCM cache cleanup solution using an MECM Configuration Baseline.
  - Discovery script reports non-persistent cache size in MB
  - Remediation script clears non-persistent cache elements (preserves content flagged "Persist in client cache")
  - `New-CCMCacheCleanupBaseline.ps1` creates the CI, Baseline, and optional deployment via ConfigurationManager cmdlets
  - Configurable threshold (default 20 GB), weekly schedule

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
