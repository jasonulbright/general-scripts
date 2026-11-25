# PowerShell Script Block Logging

Enables PowerShell Script Block Logging (EnableScriptBlockLogging = 1) for detection/forensics (event 4104). The most useful PowerShell detective control; absent from most homegrown baselines because its absence is invisible until you need the logs. Detective only, safe to enable broadly. Single DWORD; no reboot.

## Files

| File | Purpose |
|------|---------|
| `New-ScriptBlockLoggingBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging` | `EnableScriptBlockLogging` |

## Scope

- Severity: Warning
- Reboot required: no
- Clients: Windows 8.1, Windows 10, Windows 11
- Servers: Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Compliance: PowerShell Script Block Logging`
- Configuration Baseline: `Compliance PowerShell Script Block Logging`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-ScriptBlockLoggingBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_logging_windows
