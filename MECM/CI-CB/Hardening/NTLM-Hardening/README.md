# NTLM LmCompatibilityLevel

Enforces NTLMv2-only authentication (LmCompatibilityLevel = 5; refuse LM & NTLMv1). Mitigates crackable/relayable legacy auth. Missed because nothing visibly breaks when weak protocols stay allowed. Single DWORD; no reboot. Test legacy appliances first.

## Files

| File | Purpose |
|------|---------|
| `New-NTLMHardeningBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Control\Lsa` | `LmCompatibilityLevel` |

## Scope

- Severity: Critical
- Reboot required: no
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Hardening: NTLM LmCompatibilityLevel`
- Configuration Baseline: `Hardening NTLM LmCompatibilityLevel`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-NTLMHardeningBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/network-security-lan-manager-authentication-level
