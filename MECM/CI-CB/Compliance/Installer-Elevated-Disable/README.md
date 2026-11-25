# Windows Installer AlwaysInstallElevated Disable

Disables Windows Installer AlwaysInstallElevated (HKLM = 0). Removes a textbook local privilege-escalation primitive (malicious MSI -> SYSTEM). Buried in a rarely visited Installer policy node, so commonly missed. Single DWORD; no reboot. HKCU copy is per-user; HKLM=0 alone neutralizes elevation.

## Files

| File | Purpose |
|------|---------|
| `New-NoElevatedInstallBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SOFTWARE\Policies\Microsoft\Windows\Installer` | `AlwaysInstallElevated` |

## Scope

- Severity: Critical
- Reboot required: no
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Compliance: Windows Installer AlwaysInstallElevated Disable`
- Configuration Baseline: `Compliance Installer AlwaysInstallElevated Disable`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-NoElevatedInstallBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows/win32/msi/alwaysinstallelevated
