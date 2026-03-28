# Invoke-FactoryReset

Factory resets a Windows device using the MDM Bridge WMI provider (`MDM_RemoteWipe`). Replaces `systemreset -factoryreset` which was removed in Windows 24H2.

Works on domain-joined, workgroup, and MDM-enrolled devices without requiring Intune enrollment.

## What it does

- Triggers a full OS reset via the `MDM_RemoteWipe` CIM class
- Removes all user data, profiles, and installed applications
- Preserves the OS installation (no reimage needed)
- Device reboots into OOBE (Out-of-Box Experience)

## Usage

```powershell
# Local machine (prompts for confirmation)
.\Invoke-FactoryReset.ps1

# Remote machine, no prompt (for SCCM deployment)
.\Invoke-FactoryReset.ps1 -ComputerName PC001 -Force

# Multiple machines
.\Invoke-FactoryReset.ps1 -ComputerName PC001, PC002, PC003 -Force

# Dry run
.\Invoke-FactoryReset.ps1 -WhatIf
```

## SCCM Deployment

Create a package with this script and deploy as a program:
- Command line: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File Invoke-FactoryReset.ps1 -Force`
- Run as: SYSTEM
- Allow interaction: No

## Requirements

- Windows 10 21H2+ or Windows 11
- Local administrator (or SYSTEM for SCCM)
- PSRemoting for remote targets

## Re-enrollment after reset

After the reset, the device enters OOBE. From there:
- **Autopilot**: if the hardware hash is registered, the device auto-enrolls
- **Domain join**: tech joins the domain manually during OOBE
- **Provisioning package (.ppkg)**: apply during OOBE to install required apps (Zscaler, TeamViewer, etc.) without modifying the base WIM

## Attribution

Original concept from [r/SCCM](https://www.reddit.com/r/SCCM/comments/1rv47wj/) community discussion on Windows 24H2 factory reset alternatives.
