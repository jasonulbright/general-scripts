# Acrobat All Tools Pane Fix

Temporary Adobe-supplied workaround for the Acrobat bug where the All Tools pane disappears / goes empty on Edit PDF (bGenCoverPagesLabelStrings = 1 under FeatureLockDown). Restart Acrobat + host to apply. RETIRE once Adobe ships the permanent patch.

## Files

| File | Purpose |
|------|---------|
| `New-AcrobatAllToolsPaneFixBaseline.ps1` | Creates the ConfigMgr Configuration Item (CI) and Configuration Baseline for this control. |
| `metadata.psd1` | Describes the control: registry surface, OS scope, builder parameters, and the ConfigMgr objects that the builder creates. |

## Registry surface

| Hive | Key | Values |
|------|-----|--------|
| HKLM | `SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown` | `bGenCoverPagesLabelStrings` |

## Scope

- Severity: Warning
- Reboot required: yes
- Clients: Windows 10, Windows 11
- Servers: Server 2016, Server 2019, Server 2022, Server 2025

## ConfigMgr objects it creates

- Configuration Item: `Configuration: Acrobat All Tools Pane Fix`
- Configuration Baseline: `Configuration Acrobat All Tools Pane Fix`

## Usage

Run from a computer with the Configuration Manager console installed.

```powershell
.\New-AcrobatAllToolsPaneFixBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -CollectionName "<collection name>"
```

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `-SiteCode` | String | yes | (none) | ConfigMgr site code. |
| `-SiteServer` | String | yes | (none) | ConfigMgr site server FQDN. |
| `-CollectionName` | String | no | (none) | If specified, deploys the baseline to this collection daily. Target machines with Acrobat installed. |
| `-DetectOnly` | Switch | no | `False` | Create / deploy without remediation. |

## References

- https://community.adobe.com/questions-9/all-tools-pane-disappears-empty-when-i-select-edit-pdf-1628319
