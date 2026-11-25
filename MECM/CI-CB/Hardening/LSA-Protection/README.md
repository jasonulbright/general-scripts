# LSA Protection (RunAsPPL)

Enables LSA Protection (RunAsPPL = 1) so LSASS runs as a Protected Process Light, blocking most credential-dumping tooling. High-value, low-cost, almost always missed. REBOOT REQUIRED to engage; validate LSA plugin signing first.

## Files

| File | Purpose |
|------|---------|
| `New-LSAProtectionBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Control\Lsa` | `RunAsPPL` |

## Scope

- Severity: Critical
- Reboot required: yes
- Clients: Windows 8.1, Windows 10, Windows 11
- Servers: Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Hardening: LSA Protection (RunAsPPL)`
- Configuration Baseline: `Hardening LSA Protection RunAsPPL`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-LSAProtectionBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows-server/security/credentials-protection-and-management/configuring-additional-lsa-protection
