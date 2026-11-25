# Autorun/Autoplay Disable

Disables Autorun/Autoplay on all drive types (NoDriveTypeAutoRun = 255). Defeats malicious removable-media / mapped-share autorun infection. Long-standing CIS/STIG item dropped because Autoplay feels like UX, not attack surface. Single DWORD; no reboot.

## Files

| File | Purpose |
|------|---------|
| `New-AutorunDisableBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer` | `NoDriveTypeAutoRun` |

## Scope

- Severity: Warning
- Reboot required: no
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Compliance: Autorun/Autoplay Disable`
- Configuration Baseline: `Compliance Autorun Autoplay Disable`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-AutorunDisableBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/security-options
