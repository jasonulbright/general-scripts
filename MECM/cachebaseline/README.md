# CCM Cache Cleanup Baseline

Automated MECM Configuration Baseline that clears non-persistent CCM client cache on a weekly schedule. Content flagged "Persist in client cache" (e.g., VPN, ZPA) is never removed.

## Problem

The CCM cache limit (e.g., 40 GB) fills with stale deployment content. Once the cache approaches the limit, new deployments larger than the remaining space fail to download. Manual script runs are required to reclaim space.

## Solution

A Configuration Item with:

- **Discovery script** that returns non-persistent cache size in MB as an integer
- **Remediation script** that deletes all non-persistent cache elements
- **Compliance rule**: non-persistent cache size <= 20 GB (configurable)

The `0x200` ContentFlags bit (`PERSIST_IN_CACHE`) is checked on every cache element. Elements with this flag are skipped. The remediation uses `DeleteCacheElement` (not `DeleteCacheElementEx`) so content actively being downloaded is also skipped.

## Files

| File | Purpose |
|------|---------|
| `New-CCMCacheCleanupBaseline.ps1` | Creates the CI, Baseline, and optional deployment via MECM PowerShell cmdlets |
| `Discovery.ps1` | Standalone copy of the discovery script for reference or manual CI creation |
| `Remediation.ps1` | Standalone copy of the remediation script for reference or manual CI creation |

## Automated Deployment

Run from a machine with the MECM admin console installed:

```powershell
# Create CI + Baseline (deploy manually from console)
.\New-CCMCacheCleanupBaseline.ps1 -SiteServer sccm01.contoso.com -SiteCode MCM

# Create and auto-deploy to a collection
.\New-CCMCacheCleanupBaseline.ps1 -SiteServer sccm01.contoso.com -SiteCode MCM -CollectionName "All Workstations"

# Custom threshold (default is 20 GB)
.\New-CCMCacheCleanupBaseline.ps1 -SiteServer sccm01.contoso.com -SiteCode MCM -ThresholdGB 10
```

## Manual Deployment

If you prefer to create the CI and Baseline through the MECM console:

1. **Assets and Compliance > Compliance Settings > Configuration Items > Create**
2. Name: `CCM Cache Cleanup - Non-Persistent Content`, Type: Windows
3. Add a **Script** setting:
   - Name: `NonPersistentCacheSizeMB`
   - Data type: **Integer**
   - Discovery script: paste contents of `Discovery.ps1`, language: PowerShell, 64-bit: yes
   - Remediation script: paste contents of `Remediation.ps1`, language: PowerShell, 64-bit: yes
4. Add a compliance rule:
   - The value returned must be **Less than or equal to** `20480`
   - Noncompliance severity: **Warning**
   - Check: **Run the specified remediation script when this setting is noncompliant**
   - Check: **Report noncompliance if this setting instance is not found**
5. **Assets and Compliance > Compliance Settings > Configuration Baselines > Create**
   - Name: `CCM Cache Cleanup`
   - Add the CI from step 2
6. **Deploy** the baseline:
   - Target: your workstation collection
   - Check: **Remediate noncompliant rules when supported**
   - Schedule: Simple, every **7 days**

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SiteServer` | String | (required) | MECM site server FQDN |
| `-SiteCode` | String | (required) | MECM site code |
| `-ThresholdGB` | Int | 20 | Non-persistent cache size limit in GB |
| `-CollectionName` | String | (none) | If specified, deploys the baseline to this collection |

## What Gets Cleaned

| Content Type | Cleaned? |
|-------------|----------|
| Stale application deployments | Yes |
| Old software update content | Yes |
| Expired task sequence references | Yes |
| Content marked "Persist in client cache" | **No** |
| Content actively being downloaded | **No** |

## Requirements

- MECM admin console installed (for the `ConfigurationManager` PowerShell module)
- Sufficient permissions to create CIs, Baselines, and Deployments
- WinRM/PowerShell remoting not required (runs locally on each client via MECM agent)
