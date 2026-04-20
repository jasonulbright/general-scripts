# General Scripts

A collection of PowerShell utility scripts organized by category.

## Filesystem

| Script | Description |
|---|---|
| [rename-extensions.ps1](Filesystem/rename-extensions.ps1) | Rename file extensions for safe transfer (`.ps1` -> `.notps1`), restore with `-Undo`, zip with `-Archive` |
| [ConvertTo-Icon.ps1](Filesystem/ConvertTo-Icon.ps1) | Convert PNG/JPG/BMP to multi-size .ico file (256/48/32/16px). CLI mode (`-FileIn`/`-FileOut`) and drag-and-drop GUI mode. |

## ElevatedLauncher

| Script | Description |
|---|---|
| [ElevatedLauncher.ps1](ElevatedLauncher/ElevatedLauncher.ps1) | WinForms GUI for launching applications under alternate (elevated) credentials. Stores AES-encrypted credentials on disk and persists a user-defined app list in JSON. |

## MECM

| Script | Description |
|---|---|
| [OSD-ComputerSetup.ps1](MECM/OSD-ComputerSetup.ps1) | WinPE GUI for MECM OSD that collects a computer role (OU) and hostname, validates the hostname (8 alphanumeric chars), checks MECM for duplicates via WMI, and sets task sequence variables. Launched via ServiceUI.exe. |
| [OSD-ComputerSetup.bat](MECM/OSD-ComputerSetup.bat) | Wrapper batch file for OSD-ComputerSetup.ps1. Returns exit code 1630 on failure to halt the task sequence. |
| [Export-MECMCredential.ps1](MECM/Export-MECMCredential.ps1) | Generates AES-encrypted credential files (mecm.key, mecm.user, mecm.pass) for use by OSD-ComputerSetup.ps1 during WinPE imaging. |
| [Set-MECMManagementPoint.ps1](MECM/Set-MECMManagementPoint.ps1) | Force MECM clients to use a specific Management Point by cleaning cached MP references in registry, WMI, and CCM data stores. Supports batch deployment via PS-Remote. |
| [remove-appdeployments.ps1](MECM/remove-appdeployments.ps1) | Remove all deployments for a specific MECM application with review and confirmation. |
| [deploy-allapps.ps1](MECM/deploy-allapps.ps1) | Create a Required Install deployment for every CM application against a target collection. Lab / first-pass testing helper. |
| [deploy-undeployedapps.ps1](MECM/deploy-undeployedapps.ps1) | Create a Required Install deployment only for applications that currently have no deployment anywhere. Idempotent gap-filler. |
| [distribute-allcontent.ps1](MECM/distribute-allcontent.ps1) | Distribute content for every CM application to a DP group. Optional `-NamePattern` filter; treats "already targeted" as a non-error. |
| [remove-allapps.ps1](MECM/remove-allapps.ps1) | Bulk-remove every CM application in the site. Refuses if any application still has a deployment. |
| [remove-alldeployments.ps1](MECM/remove-alldeployments.ps1) | Remove every application deployment in the site (all apps, all collections). Destructive; intended for lab resets. |
| [remove-deploymentsbypattern.ps1](MECM/remove-deploymentsbypattern.ps1) | Remove every deployment of pattern-matched apps on a target collection without recreating any new deployment. |
| [set-availabledeployment.ps1](MECM/set-availabledeployment.ps1) | Switch pattern-matched apps from any existing deployment to a Required-less Available deployment on a collection. |
| [switch-deploymentstouninstall.ps1](MECM/switch-deploymentstouninstall.ps1) | Convert every Install deployment on a collection to an Uninstall deployment, with a `-KeepInstalledPattern` exclusion regex. |
| [cachebaseline/](MECM/cachebaseline/) | MECM Configuration Baseline for automated CCM cache cleanup. Clears non-persistent cache content on a weekly schedule while preserving pinned content. Includes CI/CB creation script, standalone discovery/remediation scripts, and deployment docs. |
| [client-check/](MECM/client-check/) | End-user self-service diagnostic tool for "I can't install this from Software Center" triage. Generates a self-contained HTML report of device state (OS, uptime, system drive free, network + MAC, computer DN + Entra join, Registry.pol signature, pending reboot, installed apps 32/64/user, MECM client status) plus the last 20 errors and warnings in a 24h window across 25+ CCM logs and the SCClient user log. Shared-read so it coexists with CcmExec; reads `.log` and `.lo_`. Banner up top tells the user to reboot before submitting a ticket when applicable. Opens in Edge. |

## HyperV

| Script | Description |
|---|---|
| [Watch-VMLog.ps1](HyperV/Watch-VMLog.ps1) | Tail a log file inside a Hyper-V VM via PowerShell Direct. Polls every N seconds, color-codes ERROR (red) and WARNING (yellow) lines. |
| [Get-VMLogInventory.ps1](HyperV/Get-VMLogInventory.ps1) | Discover running processes and log files across common paths (C:\, Windows\Temp, SMS logs, user temp) inside a Hyper-V VM. |

## Drivers

| Script | Description |
|---|---|
| [Remove-DriverStoreEntries.ps1](Drivers/Remove-DriverStoreEntries.ps1) | Remove stubborn drivers from the Windows driver store by regex pattern. Force-removes via pnputil and deletes FileRepository folders with takeown/icacls. Default pattern targets Alienware Command Center (AWCC) reinstall loop. Supports -WhatIf. |

## Registry

| Script | Description |
|---|---|
| [Remove-AppRegistryEntries.ps1](Registry/Remove-AppRegistryEntries.ps1) | Remove orphaned or corrupt application registry entries from Uninstall and Installer hives when the original MSI source is missing. Supports wildcard matching on DisplayName, DisplayVersion, and Publisher with AND logic. |
| [Search-ARPEntries.ps1](Registry/Search-ARPEntries.ps1) | Read-only ARP search across HKLM Uninstall (x64 + x86) and HKCR Installer\Products. AND-matched wildcards on DisplayName, DisplayVersion, and Publisher. |

## CodeQuality

| Script | Description |
|---|---|
| [Find-EmptyCatchBlocks.ps1](CodeQuality/Find-EmptyCatchBlocks.ps1) | AST-based finder for empty `catch {}` blocks across `.ps1` / `.psm1` files. Audit error-handling coverage in a module or script tree. |
| [Test-ScriptSyntax.ps1](CodeQuality/Test-ScriptSyntax.ps1) | AST parse-error checker across a path; returns exit code 1 when any script fails to parse. Drop-in pre-commit / CI gate. |

## DotNet

| Script | Description |
|---|---|
| [Get-AssemblyInfo.ps1](DotNet/Get-AssemblyInfo.ps1) | Reflection-based .NET DLL inspector. Enumerates public types with their declared properties, methods (excluding property accessors), and custom attributes. |

## Prerequisites

| Requirement | Details |
|---|---|
| **PowerShell** | 5.1+ |
| **MECM scripts** | ConfigurationManager module (MECM console installed) where noted |

## License

MIT
