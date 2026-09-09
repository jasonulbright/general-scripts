#Requires -Version 5.1
<#
.SYNOPSIS
    Creates six independent MECM speculative-execution remediation applications.
.DESCRIPTION
    One application and one script deployment type per tested GUI profile.
    Registry detection only, no requirements, InstallForSystem, ForceReboot.
    Does not deploy, distribute content, change local mitigations, or create
    uninstall commands. Deploy only ONE matching profile to each server.
    Values are taken from Registry\New-SpecExecBitmask.ps1 (both vendor boxes).
.PARAMETER ContentRoot
    Existing UNC source folder readable by the site server. Each profile gets
    its own SpecExec\<profile>\<ContentVersion> directory. ContentOnly also
    accepts an absolute local folder; no console or site connection is needed.
.PARAMETER ContentOnly
    Generate the six installer scripts without creating MECM objects.
.PARAMETER OnExisting
    Fail (default) stops before writes if any application already exists.
    Skip leaves existing single-DT applications and their content untouched.
    Repair updates only download/reboot/runtime settings on this creator's
    existing single DT, then creates missing applications. Content is untouched.
    An existing application with zero or multiple DTs always requires review.
.PARAMETER ContentVersion
    Content revision, not a Windows or mitigation version. Existing different
    content is never overwritten. Default: 1.0.
.EXAMPLE
    .\New-SpecExecApplications.ps1 -ContentOnly -ContentRoot C:\temp\SpecExec
.EXAMPLE
    .\New-SpecExecApplications.ps1 -SiteCode MCM -SiteServer cm01.contoso.com -ContentRoot \\fileserver\Sources\Remediations
.EXAMPLE
    .\New-SpecExecApplications.ps1 -SiteCode MCM -SiteServer cm01.contoso.com -ContentRoot \\fileserver\Sources\Remediations -WhatIf
.NOTES
    Run creation in Windows PowerShell 5.1 with the ConfigMgr console installed.
    Creation needs application-management rights and source-folder write access.
    Registry detection means configured, not proof of active protection or reboot.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Create')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Create')]
    [ValidatePattern('^[A-Za-z0-9]{3}$')][string]$SiteCode,
    [Parameter(Mandatory, ParameterSetName = 'Create')]
    [ValidateNotNullOrEmpty()][string]$SiteServer,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ContentRoot,
    [Parameter(Mandatory, ParameterSetName = 'ContentOnly')][switch]$ContentOnly,
    [ValidatePattern('^\d+(\.\d+){1,3}$')][string]$ContentVersion = '1.0',
    [ValidatePattern('\S')][ValidateLength(1, 120)]
    [string]$NamePrefix = 'Speculative Execution Mitigations',
    [ValidateSet('Fail', 'Skip', 'Repair')][string]$OnExisting = 'Fail'
)

function Get-SpecExecProfiles {
    $vendors = @(
        @{ Id = 'Intel-HT-On';  Label = 'Intel - HT Enabled';  Override = 0x00800048 }
        @{ Id = 'Intel-HT-Off'; Label = 'Intel - HT Disabled'; Override = 0x00802048 }
        @{ Id = 'AMD';          Label = 'AMD';                 Override = 0x05000040 }
    )
    foreach ($hyperV in $false, $true) {
        foreach ($vendor in $vendors) {
            [pscustomobject]@{
                Id       = $vendor.Id + $(if ($hyperV) { '-HyperV' } else { '-Standard' })
                Label    = $vendor.Label + $(if ($hyperV) { ' - Hyper-V Host' } else { ' - Standard' })
                Override = [int]$vendor.Override
                HyperV   = $hyperV
            }
        }
    }
}

function Get-SpecExecSettings {
    param([Parameter(Mandatory)]$Profile)
    $memoryKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    [pscustomobject]@{ Key = $memoryKey; Name = 'FeatureSettingsOverride'; Kind = 'DWord'; Value = [int]$Profile.Override }
    [pscustomobject]@{ Key = $memoryKey; Name = 'FeatureSettingsOverrideMask'; Kind = 'DWord'; Value = 3 }
    if ($Profile.HyperV) {
        [pscustomobject]@{
            Key = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization'
            Name = 'MinVmVersionForCpuBasedMitigations'; Kind = 'String'; Value = '1.0'
        }
    }
}

function New-SpecExecInstallerText {
    param([Parameter(Mandatory)]$Profile)
    $literalSettings = foreach ($setting in @(Get-SpecExecSettings -Profile $Profile)) {
        $value = if ($setting.Kind -eq 'DWord') { '[int]{0}' -f $setting.Value } else { "'" + $setting.Value + "'" }
        "    @{ Key = '$($setting.Key)'; Name = '$($setting.Name)'; Kind = '$($setting.Kind)'; Value = $value }"
    }
    # This template is self-contained; it never imports the creator or App Packager.
    $template = @'
#Requires -Version 5.1
# Profile: __PROFILE__
# Applies the exact approved values. No hardware checks and no direct restart.
$ErrorActionPreference = 'Stop'

function Set-SpecExecRegistryValues {
    param([Parameter(Mandatory)]$RegistryBase, [Parameter(Mandatory)][object[]]$Settings)
    foreach ($setting in $Settings) {
        $key = $null
        try {
            $key = $RegistryBase.CreateSubKey($setting.Key)
            if ($null -eq $key) { throw "Cannot open HKLM\$($setting.Key) for writing." }
            $kind = [Microsoft.Win32.RegistryValueKind]$setting.Kind
            $key.SetValue($setting.Name, $setting.Value, $kind)
            if ($key.GetValueKind($setting.Name) -ne $kind -or
                $key.GetValue($setting.Name) -cne $setting.Value) {
                throw "Registry read-back failed: HKLM\$($setting.Key)\$($setting.Name)"
            }
            Write-Output "Verified HKLM\$($setting.Key)\$($setting.Name) = $($setting.Value) ($kind)"
        }
        finally { if ($null -ne $key) { $key.Dispose() } }
    }
}

$settings = @(
__SETTINGS__
)
$registryBase = $null
$result = 1
try {
    $registryBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
    Set-SpecExecRegistryValues -RegistryBase $registryBase -Settings $settings
    Write-Output 'Configuration applied. A reboot is required; ConfigMgr manages the restart.'
    $result = 3010
}
catch {
    [Console]::Error.WriteLine("SpecExec remediation failed: $($_.Exception.Message)")
}
finally { if ($null -ne $registryBase) { $registryBase.Dispose() } }
exit $result
'@
    return ($template.Replace('__PROFILE__', $Profile.Label).Replace('__SETTINGS__', ($literalSettings -join "`r`n")) -replace '\r?\n', "`r`n") + "`r`n"
}

function Connect-SpecExecSite {
    param([string]$Code, [string]$Server)
    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Create the applications in Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.'
    }
    if (-not (Get-Module ConfigurationManager)) {
        $modulePath = if ($env:SMS_ADMIN_UI_PATH) {
            Join-Path (Split-Path $env:SMS_ADMIN_UI_PATH -Parent) 'ConfigurationManager.psd1'
        }
        if ($modulePath -and (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
            Import-Module $modulePath -Global -ErrorAction Stop
        }
        else { Import-Module ConfigurationManager -Global -ErrorAction Stop }
    }
    $drive = Get-PSDrive -Name $Code -PSProvider CMSite -ErrorAction SilentlyContinue
    if ($drive -and $drive.Root.TrimEnd('.') -ine $Server.TrimEnd('.')) {
        throw "Existing ${Code}: drive targets '$($drive.Root)', not '$Server'. Use the matching SMS Provider server name."
    }
    if (-not $drive) {
        # The local connection is needed for read-only preflight, including WhatIf.
        New-PSDrive -Name $Code -PSProvider CMSite -Root $Server -Scope Script -WhatIf:$false -Confirm:$false -ErrorAction Stop | Out-Null
    }
    Set-Location "${Code}:\" -ErrorAction Stop
}

function Test-SpecExecContent {
    param([string]$Path, [string]$Text)
    if ([IO.File]::Exists($Path) -and [IO.File]::ReadAllText($Path) -cne $Text) {
        throw "Different content already exists at '$Path'. Use a new ContentVersion; existing content will not be overwritten."
    }
    if ([IO.Directory]::Exists($Path)) { throw "Expected a file but found a directory: $Path" }
}

function Write-SpecExecContent {
    param([string]$Path, [string]$Text)
    Test-SpecExecContent -Path $Path -Text $Text
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    if (-not [IO.File]::Exists($Path)) {
        # CreateNew prevents a concurrent run from replacing published content.
        $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally { $stream.Dispose() }
    }
}

function New-SpecExecDetectionClauses {
    param([Parameter(Mandatory)]$Profile)
    foreach ($setting in @(Get-SpecExecSettings -Profile $Profile)) {
        $parameters = @{
            Hive = 'LocalMachine'; KeyName = $setting.Key; ValueName = $setting.Name
            PropertyType = $(if ($setting.Kind -eq 'DWord') { 'Integer' } else { 'String' })
            Value = $true; ExpressionOperator = 'IsEquals'; ExpectedValue = [string]$setting.Value
            ErrorAction = 'Stop'
        }
        # Omit Is64Bit: this cmdlet's switch selects the 32-bit-app registry view.
        New-CMDetectionClauseRegistryKeyValue @parameters
    }
}

function Set-SpecExecDeploymentOptions {
    param([Parameter(Mandatory)][string]$ApplicationName)
    # Set explicitly after Add as well as during repair, so both content-tab
    # controls are persisted together. Application names survive CI revisions.
    Set-CMScriptDeploymentType -ApplicationName $ApplicationName -DeploymentTypeName 'Apply registry mitigation' `
        -DisableWildcardHandling -ContentFallback $true -SlowNetworkDeploymentMode Download `
        -EstimatedRuntimeMins 15 -MaximumRuntimeMins 20 -RebootBehavior ForceReboot `
        -Confirm:$false -ErrorAction Stop | Out-Null
}

function Resolve-SpecExecContentRoot {
    param([string]$Path, [switch]$ContentOnly)
    if ($Path -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') {
        throw 'ContentRoot must be an absolute Windows directory or UNC path.'
    }
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $ContentOnly -and ($resolved -notmatch '^\\\\[^\\]+\\[^\\]+' -or
        -not [IO.Directory]::Exists($resolved))) {
        throw 'Application creation requires an existing UNC ContentRoot readable by the site server.'
    }
    return $resolved
}

function Invoke-SpecExecApplicationCreation {
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$SiteCode, [string]$SiteServer,
    [Parameter(Mandatory)][string]$ContentRoot, [switch]$ContentOnly,
    [string]$ContentVersion = '1.0',
    [string]$NamePrefix = 'Speculative Execution Mitigations',
    [ValidateSet('Fail', 'Skip', 'Repair')][string]$OnExisting = 'Fail'
)
$ErrorActionPreference = 'Stop'
$ContentRoot = Resolve-SpecExecContentRoot -Path $ContentRoot -ContentOnly:$ContentOnly
$originalLocation = Get-Location
try {
    if (-not $ContentOnly) { Connect-SpecExecSite -Code $SiteCode -Server $SiteServer }
    $plans = @(foreach ($profile in @(Get-SpecExecProfiles)) {
        $name = '{0} - {1}' -f $NamePrefix.Trim(), $profile.Label
        $directory = [IO.Path]::Combine($ContentRoot, 'SpecExec', $profile.Id, $ContentVersion)
        $path = [IO.Path]::Combine($directory, 'Install-SpecExec.ps1')
        $text = New-SpecExecInstallerText -Profile $profile
        $skip = $false
        $repair = $false
        $existingId = $null
        if (-not $ContentOnly) {
            $existing = @(Get-CMApplication -Name $name -DisableWildcardHandling -ErrorAction Stop)
            if ($existing.Count -gt 1) { throw "Multiple applications named '$name'. Resolve duplicates first." }
            if ($existing.Count -eq 1) {
                if ($OnExisting -eq 'Fail') { throw "Application '$name' already exists. Use -OnExisting Skip to leave it unchanged." }
                $existingDts = @(Get-CMDeploymentType -ApplicationName $name -DisableWildcardHandling -ErrorAction Stop)
                if ($existingDts.Count -ne 1) { throw "Existing application '$name' has $($existingDts.Count) DTs. Review it in the console before retrying." }
                $repair = ($OnExisting -eq 'Repair')
                if ($repair -and $existingDts[0].LocalizedDisplayName -cne 'Apply registry mitigation') {
                    throw "Existing application '$name' has an unexpected DT name; refusing to repair it."
                }
                $existingId = [int]$existing[0].CI_ID
                $skip = -not $repair
            }
        }
        if (-not $skip -and -not $repair) { Test-SpecExecContent -Path $path -Text $text }
        [pscustomobject]@{ Name = $name; Profile = $profile; Directory = $directory; Path = $path; Text = $text; Skip = $skip; Repair = $repair; ExistingId = $existingId }
    })

    foreach ($plan in $plans) {
        $status = 'Skipped'
        $applicationId = $null
        if ($plan.Skip) { Write-Warning "Left existing application and content unchanged: $($plan.Name)" }
        elseif ($plan.Repair) {
            $applicationId = $plan.ExistingId
            if ($PSCmdlet.ShouldProcess($plan.Name, 'Repair existing DT download, reboot and runtime settings; preserve content and detection')) {
                Set-SpecExecDeploymentOptions -ApplicationName $plan.Name
                $status = 'Repaired'
            }
            else { $status = 'WhatIf' }
        }
        elseif ($PSCmdlet.ShouldProcess($plan.Name, $(if ($ContentOnly) { 'Generate installer content' } else { 'Create content, application and one ForceReboot deployment type' }))) {
            Write-SpecExecContent -Path $plan.Path -Text $plan.Text
            $status = 'ContentOnly'
            if (-not $ContentOnly) {
                # Build detection outside the CMSite provider, as in the tested packagers.
                Push-Location -LiteralPath $PSScriptRoot
                try { $clauses = @(New-SpecExecDetectionClauses -Profile $plan.Profile) }
                finally { Pop-Location }
                $description = "Profile: $($plan.Profile.Label). FeatureSettingsOverride=0x{0:X8}; Mask=3. " -f $plan.Profile.Override
                $description += 'Registry configuration only; restart required. No hardware requirements. Deploy only this matching profile; do not overlap SpecExec deployments. No uninstall.'
                $app = New-CMApplication -Name $plan.Name -Publisher 'Microsoft' -SoftwareVersion $ContentVersion `
                    -Description $description -AutoInstall $true -ErrorAction Stop
                $applicationId = [int]$app.CI_ID
                $dtStep = 'creation'
                try {
                    $dtParameters = @{
                        ApplicationId = $applicationId; DeploymentTypeName = 'Apply registry mitigation'
                        ContentLocation = $plan.Directory
                        InstallCommand = 'PowerShell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "Install-SpecExec.ps1"'
                        AddDetectionClause = $clauses
                        DetectionClauseConnector = @(for ($i = 1; $i -lt $clauses.Count; $i++) {
                            @{ LogicalName = $clauses[$i].Setting.LogicalName; Connector = 'And' }
                        })
                        InstallationBehaviorType = 'InstallForSystem'
                        LogonRequirementType = 'WhetherOrNotUserLoggedOn'; UserInteractionMode = 'Hidden'
                        RebootBehavior = 'ForceReboot'; EstimatedRuntimeMins = 15; MaximumRuntimeMins = 20
                        ContentFallback = $true; SlowNetworkDeploymentMode = 'Download'; ErrorAction = 'Stop'
                    }
                    Add-CMScriptDeploymentType @dtParameters | Out-Null
                    $dtStep = 'download/reboot/runtime configuration'
                    Set-SpecExecDeploymentOptions -ApplicationName $plan.Name
                    $dtStep = 'verification'
                    $dts = @(Get-CMDeploymentType -ApplicationName $plan.Name -DisableWildcardHandling -ErrorAction Stop)
                    if ($dts.Count -ne 1) { throw "Expected exactly one deployment type; received $($dts.Count)." }
                }
                catch {
                    throw "Application '$($plan.Name)' (CI_ID $applicationId) was created, but DT $dtStep failed. Review this application before retrying. $($_.Exception.Message)"
                }
                $status = 'Created'
            }
        }
        else { $status = 'WhatIf' }
        [pscustomobject]@{
            Application = $plan.Name; Status = $status; CI_ID = $applicationId
            ContentPath = $(if ($plan.Skip -or $plan.Repair) { $null } else { $plan.Directory })
            Override = ('0x{0:X8}' -f $plan.Profile.Override); Mask = 3; HyperV = $plan.Profile.HyperV
        }
    }
}
finally { Set-Location -LiteralPath $originalLocation.Path }
}

# Dot-source for tests or access to the profile/content functions without running.
if ($MyInvocation.InvocationName -eq '.') { return }
Invoke-SpecExecApplicationCreation @PSBoundParameters
