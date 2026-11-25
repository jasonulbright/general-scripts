# User Profile Cleanup

Removes stale and orphaned user profile data from Windows clients and servers. One engine, three ways to run it. The number of days of inactivity (30, 60, 90 and so on) is asked when the ConfigMgr objects are created, and it is part of their names, so several day counts can exist side by side.

| Option | Script | Creates | Use it for |
|--------|--------|---------|------------|
| Configuration Item + Baseline | `New-UserProfileCleanupBaseline.ps1` | `Maintenance: User Profile Cleanup - 90 Days` (CI) and `Maintenance User Profile Cleanup - 90 Days` (baseline) | Continuous compliance. Discovery counts the items, remediation removes them. |
| Package + program | `New-UserProfileCleanupPackage.ps1` | `Maintenance: User Profile Cleanup (Package) - 90 Days`, program `Clean up user profiles (90 days)`, optional required deployment on a recurring schedule | A scheduled run on a collection. |
| Task sequence step | the same package | nothing more: add a Run Command Line step that uses the package | A cleanup inside an OS upgrade, refresh or maintenance task sequence. |
| By hand | `Invoke-UserProfileCleanup.ps1` | nothing | One computer, or a different tool such as a scheduled task. |

## What it cleans

| Kind | What qualifies | What is removed |
|------|----------------|-----------------|
| `StaleProfile` | A registered profile that is not loaded and was not used for N days or more | Profile folder (all user data), user registry hive (`NTUSER.DAT`), `ProfileList` registration. The profile service does the removal (`Win32_UserProfile`). |
| `OrphanRegistration` | A `ProfileList` key, including `.bak` keys, whose profile folder no longer exists | The key (through the profile service when it knows the profile) |
| `OrphanProfileGuid` | A `ProfileGuid` key whose `SidString` names a SID that has no `ProfileList` key | The key |
| `OrphanFolder` | A profile-shaped folder (has `NTUSER.DAT`, `NTUSER.MAN` or `AppData`) in the profiles directory that no `ProfileList` key points to, and that is N days old or older | The folder. Junctions and symbolic links are removed as links. Their targets are never opened. |

## What it never touches

- A loaded profile (a user who is signed in, or a hive that is loaded).
- A SID that is not a local, domain or Entra ID user (`S-1-5-21-` and `S-1-12-1-` only). This keeps system, service and virtual-account profiles safe.
- A well-known account: any `S-1-5-21-` SID with a RID below 1000 (Administrator 500, Guest 501, DefaultAccount 503, WDAGUtilityAccount 504).
- A profile folder that is not a direct child of the profiles directory (`C:\Users` by default), that has a system name (`Default`, `Public` and so on), or that another `ProfileList` key also points to (the other key's user may be signed in).
- A profile that has no usable timestamp. Unknown age is never old.
- `Default`, `Default User`, `Default.migrated`, `All Users`, `Public`, `LocalService`, `NetworkService`.
- A folder that is not profile-shaped, and an orphan folder younger than N days (this protects a profile that is being created).
- Any account that matches `-ExcludeAccounts`.

## How profile age is measured

The method follows the Microsoft Learn page "Scripts: Retrieve profile age" (Windows 10 version 1809 and later). The profile service stores `LocalProfileLoadTime`, `LocalProfileUnLoadTime` and `LocalProfileCleanupCheckTime` in the profile's `ProfileList` key. The newest of the three is the last use. When none exists, the write time of `NTUSER.MAN` or `NTUSER.DAT` is used. `Win32_UserProfile.LastUseTime` is not used: it is empty for Entra ID accounts. One day is 24 hours.

## Usage: package on a recurring schedule

`New-UserProfileCleanupPackage.ps1` stages the content, creates the package and one program, and (optional) distributes it and creates a required deployment that reruns every N days. The program runs hidden, with administrative rights, whether or not a user is signed in.

```powershell
# Ask for the day count, create the package + program (not distributed, not deployed)
.\New-UserProfileCleanupPackage.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -SourcePath \\CM01\Sources$\Packages\ProfileCleanup90

# 90 days, distribute, run every 7 days on a collection
.\New-UserProfileCleanupPackage.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -SourcePath \\CM01\Sources$\Packages\ProfileCleanup90 `
    -Days 90 -ExcludeAccounts 'svc_*' -DistributionPointGroupName 'All DPs' -CollectionName 'All Workstations' -ScheduleDays 7

# Write the content and print the command lines. No ConfigMgr connection.
.\New-UserProfileCleanupPackage.ps1 -StageOnly -SourcePath C:\Temp\ProfileCleanup -Days 60
```

The package content is `Invoke-UserProfileCleanup.ps1`, `UserProfileCleanup.Engine.ps1` and a generated `Run-UserProfileCleanup.ps1` that holds the chosen settings. The program command line is short and has no quoting problems:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Run-UserProfileCleanup.ps1
```

A package program starts a 32-bit PowerShell on a 64-bit Windows (Microsoft Learn, "Packages and programs in Configuration Manager"). The runner starts the 64-bit PowerShell itself, so the registry and system folders are not redirected.

Use one source folder for each package (the day count and the exclude list are in the generated wrapper).

A required deployment honors maintenance windows. When a collection has no open window, the program waits (the client log `execmgr.log` shows "waiting for service window"). Add `-RunOutsideMaintenanceWindow` to let the program run when the deadline passes.

## Usage: task sequence step

1. Create the package with the script above (distribute it, no deployment).
2. In the task sequence, add **General > Run Command Line** in the full OS. The step does not run in WinPE: there are no profiles there.
3. Command line: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Run-UserProfileCleanup.ps1`
4. Select the package. Optional: select **Disable 64-bit file system redirection**. The runner already starts the 64-bit PowerShell when needed.
5. Exit code `0` means the run finished. Exit code `1` means one or more items could not be removed (see the log). Select **Continue on error** when that must not stop the task sequence. Exit code `2` means the content or a setting is not valid.

For a one-off step you can skip the wrapper and pass the settings on the command line:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $ErrorActionPreference='Stop'; try { .\Invoke-UserProfileCleanup.ps1 -Days 60 -ExcludeAccounts @('svc_*') } catch { exit 2 }; if ($null -eq $LASTEXITCODE) { exit 2 }; exit $LASTEXITCODE }"
```

The error handling in that form makes a failed start return `2` instead of `0`. The generated `Run-UserProfileCleanup.ps1` has the same handling.

`-DetectOnly` lists the items and removes nothing. The log is `%windir%\CCM\Logs\UserProfileCleanup.log`.

## Usage: Configuration Item and baseline

Run from a computer with the Configuration Manager console installed.

```powershell
# Ask for the day count, create the CI + baseline (not deployed)
.\New-UserProfileCleanupBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com

# 90 days, keep service and kiosk accounts, deploy weekly with remediation
.\New-UserProfileCleanupBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -Days 90 `
    -ExcludeAccounts 'svc_*', 'CONTOSO\kiosk*' -CollectionName "All Workstations"

# Report only: no remediation script, no enforcement
.\New-UserProfileCleanupBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -Days 60 -DetectOnly -CollectionName "Pilot"

# Write the scripts for review or manual CI creation. No ConfigMgr connection.
.\New-UserProfileCleanupBaseline.ps1 -ScriptOnly -OutputFolder C:\Temp\Cleanup -Days 30
```

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SiteCode` | (required) | ConfigMgr site code |
| `-SiteServer` | (required) | Site server FQDN (SMS Provider) |
| `-Days` | asks | Days of inactivity, 1 to 3650. The script asks when it is missing. |
| `-ExcludeAccounts` | none | Wildcard patterns to keep. Matched against the SID, the profile folder name, the account name and `DOMAIN\name`. |
| `-IncludeAccounts` | `*` | Wildcard patterns. When set, only matching accounts are cleaned. |
| `-Scope` | all four kinds | Kinds to clean: `StaleProfile`, `OrphanRegistration`, `OrphanProfileGuid`, `OrphanFolder` |
| `-CollectionName` | none | Deploys the baseline to this collection |
| `-ScheduleDays` | 7 | Evaluation interval of the deployment, in days |
| `-DetectOnly` | off | No remediation script and no enforcement |
| `-ScriptOnly`, `-OutputFolder` | off | Write the discovery and remediation scripts and stop |

A pattern with a backslash (`CONTOSO\kiosk*`) makes the client resolve account names. A pattern without a backslash is matched against the SID and the profile folder name only, which needs no name lookup.

The creator checks each pattern. A pattern must be printable ASCII (a typographic quote or an accented letter is refused) and a valid wildcard (`svc_[` is refused). An unregistered folder has no SID, so it is matched on its folder name. A `DOMAIN\name` pattern also matches the `name` part for such a folder, so an exclude pattern keeps the folder.

## How the CI works

| Part | Value |
|------|-------|
| Setting | `UserProfileCleanupItemCount`, data type Integer, PowerShell, 64-bit |
| Discovery script | Returns the number of items that qualify |
| Compliance rule | The value must equal `0`. Severity Warning. Remediates when non-compliant (not with `-DetectOnly`). |
| Remediation script | Removes the items in two passes (the second pass removes the `ProfileGuid` keys that the first pass orphaned) |
| Client log | `%windir%\CCM\Logs\UserProfileCleanup.log`, one line for each removed item, rolled to `.lo_` at 1 MB |

The discovery and remediation scripts contain the engine text (`UserProfileCleanup.Engine.ps1`, comments removed) and the settings chosen at creation. The client reads no file from the share. To change a setting, create a new CI. The CI scripts are about 21 KB each.

## Files

| File | Purpose |
|------|---------|
| `New-UserProfileCleanupBaseline.ps1` | Asks for the day count, builds the scripts, creates the CI, baseline and optional deployment |
| `New-UserProfileCleanupPackage.ps1` | Asks for the day count, stages the content, creates the package, program, optional distribution and recurring deployment |
| `Invoke-UserProfileCleanup.ps1` | The runner for a package program, a task sequence step or a manual run. Exit codes 0, 1, 2. |
| `UserProfileCleanup.Engine.ps1` | The cleanup logic. Functions only. `Get-UserProfileCleanupItem` reads, `Remove-UserProfileCleanupItem` removes (supports `-WhatIf`). |
| `*.Tests.ps1` | Pester tests, one file for each script above. They create real local test users and profiles. Run on a lab client. |
| `metadata.psd1` | Description of the control, for the other builders in this folder tree |

## Failed creation

Each creator removes what it made (the CI and baseline, or the package) when a later step fails, for example a collection name that does not exist. The next run is then not blocked by the "already exists" check.

## Tests

Run each test file in its own PowerShell process, on a lab client, elevated. The engine tests create local users named `zzpc-*` with real profiles (`CreateProfile`) and remove them. Every query uses an include pattern, so a real profile is never selected. The generator tests use stub ConfigMgr cmdlets, and the last block runs the generated scripts on a real test profile. Running both files in one remote PowerShell session ended with a call-depth error in Pester (observed 2026-11-25; the cause was not found). Separate processes run clean.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path .\UserProfileCleanup.Engine.Tests.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester -Path .\New-UserProfileCleanupBaseline.Tests.ps1"
```

## Try it on one computer first

```powershell
. .\UserProfileCleanup.Engine.ps1
Get-UserProfileCleanupItem -MaxAgeDays 90 | Format-Table Kind, Account, AgeDays, Basis, Path
Get-UserProfileCleanupItem -MaxAgeDays 90 | Remove-UserProfileCleanupItem -WhatIf
```

## Cautions

- A removed profile is not recoverable. Data that is not synced elsewhere (OneDrive Known Folder Move, folder redirection, roaming profile) is lost. Roaming and domain users get a fresh profile at the next sign-in.
- Start with `-DetectOnly` on a pilot collection. Compliance reports then show how many items each computer has.
- Use one day count for each collection. Two baselines with different day counts on the same computer both run. The shorter one decides.
- The Group Policy "Delete user profiles older than a specified number of days on system restart" does the same job for stale profiles. Do not enable both without a reason. See the Microsoft Learn page "User profiles older than a specified number of days aren't deleted as expected on system restart" for the ConfigMgr "Enable User Data and Profiles" interaction.

## Sources (Microsoft Learn)

- Scripts: Retrieve profile age and optionally delete aged copies (`learn.microsoft.com/troubleshoot/windows-server/support-tools/scripts-retrieve-profile-age-delete-aged-copies`)
- Scripts: Retrieve profile age (`.../scripts-to-retrieve-profile-age`)
- Scripts: Clean up profile folder information and prevent TEMP user profiles from being created (`.../scripts-to-cleanup-profile-folder-information-and-prevent-temp-user-profiles-from-being-created`)
- `Add-CMComplianceSettingScript`, `New-CMBaselineDeployment` (ConfigurationManager module reference)
- `CreateProfile` (userenv.h), used by the tests to build real profiles
