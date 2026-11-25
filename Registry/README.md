# Registry

Tools that search, clean or build registry data.

## Contents

| File | Purpose |
|------|---------|
| `New-SpecExecBitmask.ps1` | WPF window that builds the `FeatureSettingsOverride` and `FeatureSettingsOverrideMask` values from the mitigations you select (Intel bundle, BHI, AMD Branch Type Confusion, AMD Inception) and the Hyper-Threading state. It writes a small remediation script. The bit values follow KB4072698 and KB4073119. Target collections: `MECM/Collections/New-SpecExecTargetCollections.ps1`. |
| `Remove-AppRegistryEntries.ps1` | Removes orphaned or corrupt application entries from the Uninstall and Installer hives when the original MSI source is missing. Matches wildcards on DisplayName, DisplayVersion and Publisher (all must match). |
| `Search-ARPEntries.ps1` | Read-only search of the Add/Remove Programs entries (HKLM Uninstall, 64-bit and 32-bit, and HKCR `Installer\Products`) by DisplayName, version and Publisher. |

## Requirements

PowerShell 5.1 or later. The two scripts that change the registry need an elevated session.
