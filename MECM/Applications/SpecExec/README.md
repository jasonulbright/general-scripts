# SpecExec applications

Standalone creator: six applications, **one deployment type each**. No custom
requirements, global conditions, baselines, deployments, or App Packager dependency.

| Profile | FeatureSettingsOverride (DWORD) | Hyper-V value |
|---|---|---|
| Intel - HT Enabled - Standard | `0x00800048` | Not written |
| Intel - HT Disabled - Standard | `0x00802048` | Not written |
| AMD - Standard | `0x05000040` | Not written |
| Intel - HT Enabled - Hyper-V Host | `0x00800048` | `1.0` (REG_SZ) |
| Intel - HT Disabled - Hyper-V Host | `0x00802048` | `1.0` (REG_SZ) |
| AMD - Hyper-V Host | `0x05000040` | `1.0` (REG_SZ) |

All profiles set `FeatureSettingsOverrideMask` to DWORD `3`. Override and mask
live under `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management`.
Hyper-V profiles additionally set `MinVmVersionForCpuBasedMitigations` under
`HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization`.
Values match [the existing GUI](../../../Registry/New-SpecExecBitmask.ps1)
with both Intel/shared boxes or both AMD boxes checked, respectively.

## Run

Generate content locally for review (does not run the installers):

```powershell
.\New-SpecExecApplications.ps1 -ContentOnly -ContentRoot C:\temp\SpecExec
```

Create from **Windows PowerShell 5.1** on a machine with the ConfigMgr console:

```powershell
.\New-SpecExecApplications.ps1 -SiteCode MCM -SiteServer cm01.contoso.com `
    -ContentRoot '\\fileserver\Sources\Remediations' -WhatIf

# Remove -WhatIf to create the six applications and their source content.
```

`SiteServer` is the SMS Provider server. The UNC root must already exist and
be readable by the site server; the operator needs source-folder write access
and application-management rights. Distribute content and create the Required
deployments yourself after reviewing the applications.

## Behavior

- **Target exactly one matching profile per server.** There are no hardware
  safeguards. Conflicting apps/baselines can repeatedly overwrite these values.
  Coordinate retirement of the old SpecExec deployment before rollout.
- Each DT installs as SYSTEM, uses native registry equality clauses joined by
  AND, and sets **ForceReboot** (ConfigMgr client forces a mandatory restart).
  Restart timing remains subject to deployment/client settings and maintenance
  windows. The installer does not call Restart-Computer or shut down VMs.
- Installers write the exact profile values in the native registry view, verify
  their types/values, return `3010` on success and `1` on failure. Existing
  override bits are replaced, matching the tested GUI. A partial failure may
  leave some values written; the error is reported, not hidden as success.
- No uninstall command: removing security settings is not an uninstall operation.
- Existing apps cause a preflight failure. `-OnExisting Skip` leaves existing
  single-DT apps unchanged; it does not repair or validate their configuration.
  Incomplete/multi-DT apps require console review. Existing differing source
  content is never overwritten; use a new `-ContentVersion` for changed content.
- If creation fails partway, already-created apps/content remain. The error names
  any newly created app whose DT needs review. No automatic cleanup or deployment.
- Registry detection proves configuration only. An already-detected app will not
  run or trigger another reboot. OS/firmware prerequisites, actual protection,
  SMT policy and Hyper-V VM shutdown/startup remain the server team's responsibility.

References: [Microsoft mitigation guidance](https://support.microsoft.com/en-us/topic/kb4072698-windows-server-and-azure-stack-hci-guidance-to-protect-against-silicon-based-microarchitectural-and-speculative-execution-side-channel-vulnerabilities-2f965763-00e2-8f98-b632-0d96f30c8c8e),
[DT reboot behavior](https://learn.microsoft.com/en-us/powershell/module/configurationmanager/add-cmscriptdeploymenttype#-rebootbehavior).

## Tests

```powershell
Invoke-Pester .\New-SpecExecApplications.Tests.ps1
```

Offline tests use a fake registry and mocked MECM commands. They do not apply
mitigations or restart a machine. A live site/client pilot is still required.
