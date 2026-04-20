# Changelog

All notable changes to General Scripts are documented in this file.

## [1.0.9] - 2026-04-20

### Added
- **CodeQuality/Find-EmptyCatchBlocks.ps1** -- AST-based finder for empty `catch {}` blocks across `.ps1` / `.psm1` files; useful for auditing error-handling coverage in a module or script tree.
- **CodeQuality/Test-ScriptSyntax.ps1** -- AST parse-error checker across a path; returns exit code 1 when any script fails to parse. Drop-in pre-commit / CI gate.
- **DotNet/Get-AssemblyInfo.ps1** -- Reflection-based .NET DLL inspector. Enumerates all public types with their declared properties, methods (excluding property accessors), and custom attributes. Useful when decompiling or retargeting a vendored library.
- **Registry/Search-ARPEntries.ps1** -- Searches HKLM Uninstall (both bitnesses) and HKCR Installer\Products by DisplayName, version, and Publisher with AND-matched wildcard logic. Complements Remove-AppRegistryEntries for read-only discovery.
- **MECM/deploy-allapps.ps1** -- Creates a Required Install deployment for every CM application against a target collection. Lab / first-pass testing helper; refuses broad collections by design.
- **MECM/deploy-undeployedapps.ps1** -- Required Install deployment only for apps that currently have no deployment anywhere; gap-filler pass. Idempotent, safe to re-run.
- **MECM/distribute-allcontent.ps1** -- Distributes content for every CM application to a DP group; treats "already targeted" as a non-error. Optional -NamePattern filter.
- **MECM/remove-allapps.ps1** -- Bulk-removes every CM application in the site; refuses if any application still has a deployment (pair with remove-alldeployments).
- **MECM/remove-alldeployments.ps1** -- Removes every application deployment across the site, regardless of target collection. Destructive; intended for lab resets.
- **MECM/remove-deploymentsbypattern.ps1** -- Removes every deployment of pattern-matched apps on a target collection without recreating any new deployment. For clearing conflicts mid-test.
- **MECM/set-availabledeployment.ps1** -- Switches pattern-matched apps from any existing deployment to a Required-less Available deployment on a collection. Built around the M365 ODT / Click-to-Run variant case.
- **MECM/switch-deploymentstouninstall.ps1** -- Converts every Install deployment on a collection to an Uninstall deployment, with a -KeepInstalledPattern regex for excluding system dependencies (VC++, WebView2, runtimes).

### Fixed
- Stripped em-dashes and en-dashes from 7 `.ps1` files (`Filesystem/ConvertTo-Icon.ps1` plus 6 new MECM helpers). PowerShell's parser is fine with them in comments, but downstream consumers (extraction, logging) and our house style disallow non-ASCII dashes in scripts.

## [1.0.8] - 2026-04-20

### Added
- **MECM/client-check/** -- end-user self-service diagnostic tool that generates a single self-contained HTML report for support triage when a user cannot install something from Software Center. Gathers OS, uptime, disks (system drive shown as "X GB free of Y GB"), network adapters with MAC + IPv4/IPv6, computer distinguishedName via ADSISearcher plus `dsregcmd /status` Entra state, Registry.pol signature health (PReg v1 check for both Machine and User scope), pending-reboot state (CBS, WU-AU, pending file rename, CCM client SDK), installed applications from HKLM 64-bit, HKLM 32-bit, and HKCU (SystemComponent=1 excluded), MECM client version, site code, MP, last policy eval / HWInv / SWInv, and the last 20 errors and warnings from 25+ CCM client logs plus the SCClient user log from %TEMP%. Time-filtered to a 24-hour window by default (-HoursBack to override), reads both `.log` and rolled `.lo_` companion, uses FileShare.ReadWrite to coexist with CcmExec. When elevated, also pulls Application + System event log events. Big red banner at the top of the report when a reboot is pending, amber when uptime exceeds 24 hours. Launches in Edge. Writes `C:\temp\<user>_<host>_<timestamp>.html`.

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
