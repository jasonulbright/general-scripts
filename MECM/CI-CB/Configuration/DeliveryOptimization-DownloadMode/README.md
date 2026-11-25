# Delivery Optimization Download Mode

Enforces the Delivery Optimization DODownloadMode policy. Clients = 0 (HTTP only, no peering); servers = 99 (HTTP only, no peering, no DO cloud service). Builds one CI + baseline per OS class, deployed to separate collections. Single DWORD; no reboot.

## Files

| File | Purpose |
|------|---------|
| `New-DODownloadModeBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` | `DODownloadMode` |

## Scope

- Severity: Warning
- Reboot required: no
- Clients: Windows 10, Windows 11
- Servers: Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Delivery Optimization: DODownloadMode (Client)`
- Configuration Item: `Delivery Optimization: DODownloadMode (Server)`
- Configuration Baseline: `Delivery Optimization DODownloadMode (Client)`
- Configuration Baseline: `Delivery Optimization DODownloadMode (Server)`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-DODownloadModeBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -ClientCollectionName "<collection name>" -ServerCollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-ClientCollectionName` | String | no | (none) | Deploy the client baseline (DODownloadMode = 0) to this collection daily. |
| `-ServerCollectionName` | String | no | (none) | Deploy the server baseline (DODownloadMode = 99) to this collection daily. |
| `-ClientDownloadMode` | String | no | `0` | Expected DODownloadMode for clients. One of 0,1,2,3,99. |
| `-ServerDownloadMode` | String | no | `99` | Expected DODownloadMode for servers. One of 0,1,2,3,99. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation (audit mode). |

## References

- https://learn.microsoft.com/windows/client-management/mdm/policy-csp-deliveryoptimization#dodownloadmode
