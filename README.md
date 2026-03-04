# General Scripts

A collection of PowerShell utility scripts organized by category.

## Filesystem

| Script | Description |
|---|---|
| [rename-extensions.ps1](Filesystem/rename-extensions.ps1) | Obfuscate or restore file extensions to bypass email attachment filters (`.ps1` -> `.notps1` and back) |

## MECM

| Script | Description |
|---|---|
| [Set-MECMManagementPoint.ps1](MECM/Set-MECMManagementPoint.ps1) | Force MECM clients to use a specific Management Point by cleaning cached MP references in registry, WMI, and CCM data stores. Supports batch deployment via PS-Remote. |
| [remove-appdeployments.ps1](MECM/remove-appdeployments.ps1) | Remove all deployments for a specific MECM application with review and confirmation |

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
