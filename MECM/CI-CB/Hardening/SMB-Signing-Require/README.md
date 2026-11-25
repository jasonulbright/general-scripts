# SMB Signing Required

Requires SMB signing on both the Workstation (client) and Server services (RequireSecuritySignature = 1). Defeats SMB relay / MITM lateral movement. Missed because the default is enabled-but-not-required, which still allows downgrade. Two DWORDs; no reboot. Test legacy SMB peers first.

## Files

| File | Purpose |
|------|---------|
| `New-SMBSigningBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters` | `RequireSecuritySignature` |
| HKLM | `SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters` | `RequireSecuritySignature` |

## Scope

- Severity: Critical
- Reboot required: no
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Hardening: SMB Signing Required`
- Configuration Baseline: `Hardening SMB Signing Required`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-SMBSigningBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows-server/storage/file-server/smb-signing-overview
