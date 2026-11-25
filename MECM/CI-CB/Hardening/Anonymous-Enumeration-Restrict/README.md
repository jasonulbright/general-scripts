# Anonymous Enumeration Restrictions

Restricts anonymous / null-session enumeration of accounts, groups, and shares (RestrictAnonymous=1, RestrictAnonymousSAM=1, EveryoneIncludesAnonymous=0). Blocks unauthenticated recon for spraying / lateral movement. Silent exposure, easy to miss. Three DWORDs; no reboot.

## Files

| File | Purpose |
|------|---------|
| `New-AnonymousEnumerationBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Control\Lsa` | `RestrictAnonymous`, `RestrictAnonymousSAM`, `EveryoneIncludesAnonymous` |

## Scope

- Severity: Critical
- Reboot required: no
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Hardening: Anonymous Enumeration Restrictions`
- Configuration Baseline: `Hardening Anonymous Enumeration Restrictions`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-AnonymousEnumerationBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/network-access-do-not-allow-anonymous-enumeration-of-sam-accounts-and-shares
