# Compliance

Baselines for settings that a compliance review expects. Each folder is one control. Open its README for the details.

## Contents

| Folder | What it enforces | Builder |
|--------|------------------|---------|
| [`Autorun-Disable/`](Autorun-Disable/) | Autorun and Autoplay off on all drive types (`NoDriveTypeAutoRun = 255`). | `New-AutorunDisableBaseline.ps1` |
| [`Installer-Elevated-Disable/`](Installer-Elevated-Disable/) | Windows Installer `AlwaysInstallElevated` off (HKLM = 0). Removes a local privilege-escalation primitive. | `New-NoElevatedInstallBaseline.ps1` |
| [`PowerShell-ScriptBlock-Logging/`](PowerShell-ScriptBlock-Logging/) | PowerShell script block logging on (`EnableScriptBlockLogging = 1`, event 4104). Detective control. | `New-ScriptBlockLoggingBaseline.ps1` |
| [`RDP-NLA-Encryption/`](RDP-NLA-Encryption/) | RDP Network Level Authentication and TLS required (`UserAuthentication = 1`, `SecurityLayer = 2`). | `New-RDPHardeningBaseline.ps1` |
| [`SMBv1-Disable/`](SMBv1-Disable/) | SMBv1 server protocol off (`LanmanServer\Parameters\SMB1 = 0`). | `New-SMBv1DisableBaseline.ps1` |
| [`TLS-Legacy-Disable/`](TLS-Legacy-Disable/) | SSL 2.0, SSL 3.0, TLS 1.0 and TLS 1.1 off, TLS 1.2 on, .NET 4.x strong crypto. 24 settings on one CI. | `New-TLSLegacyDisableBaseline.ps1` |
| [`UAC-Remote-Restriction/`](UAC-Remote-Restriction/) | UAC remote token filtering kept on (`LocalAccountTokenFilterPolicy = 0`). | `New-UACRemoteRestrictionBaseline.ps1` |
