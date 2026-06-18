# MECM Collections

Standalone PowerShell scripts that create reusable MECM device collections backed by hardware-inventory WQL queries. Each script is self-contained: connect → create collection(s) → attach query rule → trigger evaluation.

These collections serve two purposes:

1. **Targeting for CI-CB deployments** that require host-attribute segmentation (e.g., Intel HT state for the bundled speculative-execution mitigations).
2. **Audit visibility** -- the membership of a collection is itself a finding. HT-disabled workstations, BitLocker-off laptops, 32-bit OS in a 64-bit fleet, etc.

Run the scripts directly from a workstation with the MECM admin console installed.

## Catalog

| Script | Creates | Used by |
|--|--|--|
| [`New-HTBasedCollections.ps1`](New-HTBasedCollections.ps1) | "Devices: Hyperthreading Enabled" + "Devices: Hyperthreading Disabled" | `CI-CB/CVE-Remediation/Intel-SpecExec-Mitigations/` |
| [`New-OSClassCollections.ps1`](New-OSClassCollections.ps1) | "Devices: Windows Clients" (ProductType 1) + "Devices: Windows Servers" (ProductType 2/3) | `CI-CB/Configuration/DeliveryOptimization-DownloadMode/` |
| [`New-WindowsDevicesCollection.ps1`](New-WindowsDevicesCollection.ps1) | "All Windows Devices" | Fleet-wide `CI-CB/Hardening/` + `CI-CB/Compliance/` baselines |

## Convention

| | Pattern |
|--|--|
| Filename | `New-<DomainShortName>Collections.ps1` (plural when the script creates multiple related collections) |
| Sibling README | optional per-script, mandatory if WQL is non-obvious or there's lifecycle/operational guidance |
| Required params | `-SiteCode`, `-SiteServer` |
| Optional params | `-LimitingCollectionName` (default sensible per script), collection name overrides |
| Refresh type | `Both` (incremental + daily full) for hardware-inventory-driven collections; `Periodic` for static or rarely-changing definitions |
| Triggers `Invoke-CMCollectionUpdate` at end | Yes -- so the engineer doesn't sit waiting for the next scheduled refresh |
