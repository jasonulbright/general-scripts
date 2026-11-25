# TLS Legacy Disable (SCHANNEL + .NET 4.x)

Disables SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1 (server + client) in SCHANNEL, explicitly enables TLS 1.2 (server + client), and forces .NET Framework 4.x to system-default strong crypto in both 64-bit and WOW6432Node paths. 24 native DWORD settings on one CI. Reboot required for SCHANNEL reload.

## Files

| File | Purpose |
|------|---------|
| `New-TLSLegacyDisableBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server` | `Enabled`, `DisabledByDefault` |
| HKLM | `SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client` | `Enabled`, `DisabledByDefault` |
| HKLM | `SOFTWARE\Microsoft\.NETFramework\v4.0.30319` | `SchUseStrongCrypto`, `SystemDefaultTlsVersions` |
| HKLM | `SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319` | `SchUseStrongCrypto`, `SystemDefaultTlsVersions` |

## Scope

- Severity: Critical
- Reboot required: yes
- Clients: Windows 7, Windows 8.1, Windows 10, Windows 11
- Servers: Server 2008 R2, Server 2012, Server 2012 R2, Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Compliance: TLS Legacy Disable`
- Configuration Baseline: `Compliance TLS Legacy Disable`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-TLSLegacyDisableBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. |
| `-DetectOnly` | Switch | no | `False` | Create with remediation disabled. |
