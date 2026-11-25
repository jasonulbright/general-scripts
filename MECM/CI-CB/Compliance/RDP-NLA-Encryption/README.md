# RDP NLA + TLS Required

Requires RDP Network Level Authentication (UserAuthentication = 1) and TLS (SecurityLayer = 2). Removes pre-auth RDP attack surface and the legacy RDP Security Layer. Easy to miss because RDP works without them. Two DWORDs; no reboot. Harmless on non-RDP hosts (key exists by default), so deployed fleet-wide.

## Files

| File | Purpose |
|------|---------|
| `New-RDPHardeningBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp` | `UserAuthentication`, `SecurityLayer` |

## Scope

- Severity: Critical
- Reboot required: no
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Compliance: RDP NLA + TLS Required`
- Configuration Baseline: `Compliance RDP NLA TLS Required`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-RDPHardeningBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows-server/remote/remote-desktop-services/clients/remote-desktop-allow-access
