# WDigest Credential Caching Disable

Disables WDigest plaintext credential caching (UseLogonCredential = 0). Blocks Mimikatz sekurlsa::wdigest cleartext credential recovery from LSASS. Frequently missed because modern Windows defaults to safe but rarely pins the value. Single DWORD; no reboot.

## Files

| File | Purpose |
|------|---------|
| `New-WDigestDisableBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest` | `UseLogonCredential` |

## Scope

- Severity: Critical
- Reboot required: no
- Clients: Windows 8.1, Windows 10, Windows 11
- Servers: Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Hardening: WDigest Credential Caching Disable`
- Configuration Baseline: `Hardening WDigest Credential Caching Disable`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-WDigestDisableBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/troubleshoot/windows-server/windows-security/credentials-protection-management
