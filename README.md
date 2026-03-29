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
| [remove-appdeployments.ps1](MECM/remove-appdeployments.ps1) | Remove all deployments for a specific MECM application with review and confirmation |
| [cachebaseline/](MECM/cachebaseline/) | MECM Configuration Baseline for automated CCM cache cleanup. Clears non-persistent cache content on a weekly schedule while preserving pinned content. Includes CI/CB creation script, standalone discovery/remediation scripts, and deployment docs. |

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

## Prerequisites

| Requirement | Details |
|---|---|
| **PowerShell** | 5.1+ |
| **MECM scripts** | ConfigurationManager module (MECM console installed) where noted |

## License

MIT
