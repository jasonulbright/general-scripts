<#
.SYNOPSIS
    Creates a ConfigMgr CI + Baseline that cleans up stale and orphaned user profile data.

.DESCRIPTION
    Builds one script-based Configuration Item and one Configuration Baseline. The number of
    days of inactivity is part of the name of both objects, for example
    "Maintenance: User Profile Cleanup - 90 Days". The script asks for the day count when
    -Days is not given.

    What the CI cleans (see README.md for the full rules):

        StaleProfile        Profile not used for N days or more. Removes the folder (user
                            data), the user registry hive (NTUSER.DAT) and the ProfileList
                            registration through the profile service (Win32_UserProfile).
        OrphanRegistration  ProfileList key (including .bak keys) with no profile folder.
        OrphanProfileGuid   ProfileGuid key whose SID has no ProfileList key.
        OrphanFolder        Profile-shaped folder in C:\Users with no ProfileList key, older
                            than N days.

    Loaded profiles (signed-in users), the built-in Administrator, system and service
    profiles, and every account that matches -ExcludeAccounts are never touched.

    The discovery script returns the number of items that qualify (Integer). The compliance
    rule is "equals 0". The remediation script removes the items and writes a log to
    %windir%\CCM\Logs\UserProfileCleanup.log. With -DetectOnly the CI has no remediation
    script, so it can only report.

    The cleanup logic is in UserProfileCleanup.Engine.ps1 in the same folder. Its text,
    without comments, is embedded in both CI scripts together with the settings chosen
    here. The CI does not read any file on the client.

    Run this script from a computer with the Configuration Manager console installed.

.PARAMETER SiteCode
    ConfigMgr site code.

.PARAMETER SiteServer
    ConfigMgr site server FQDN (SMS Provider).

.PARAMETER Days
    Days of inactivity before a profile is cleaned up, for example 30, 60 or 90. When
    omitted, the script asks for it.

.PARAMETER ExcludeAccounts
    Wildcard patterns for accounts to keep, for example 'svc_*', 'CONTOSO\kiosk*' or a SID.
    Matched against the SID, the profile folder name, the account name and DOMAIN\name.

.PARAMETER IncludeAccounts
    Wildcard patterns. When set, only matching accounts are cleaned. Default: '*'.

.PARAMETER Scope
    Kinds of item to clean. Default: StaleProfile, OrphanRegistration, OrphanProfileGuid,
    OrphanFolder.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection. Without it the baseline is
    created but not deployed.

.PARAMETER ScheduleDays
    Evaluation interval of the deployment in days. Default: 7.

.PARAMETER DetectOnly
    Report only. The CI has no remediation script and the deployment does not enforce.

.PARAMETER AssumeConnected
    For tests. Skips the module import, the site drive and the change of location. The
    caller already has the ConfigMgr cmdlets and the right location.

.PARAMETER ScriptOnly
    Do not connect to ConfigMgr. Write the discovery and remediation scripts to
    -OutputFolder for manual CI creation or review.

.PARAMETER OutputFolder
    Folder for -ScriptOnly output.

.EXAMPLE
    .\New-UserProfileCleanupBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com

    Asks for the day count, then creates the CI and baseline. Nothing is deployed.

.EXAMPLE
    .\New-UserProfileCleanupBaseline.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -Days 90 -ExcludeAccounts 'svc_*', 'CONTOSO\kiosk*' -CollectionName "All Workstations"

    Creates "Maintenance: User Profile Cleanup - 90 Days" and deploys it weekly with
    remediation to the collection.

.EXAMPLE
    .\New-UserProfileCleanupBaseline.ps1 -ScriptOnly -OutputFolder C:\Temp\Cleanup -Days 60

    Writes the 60-day discovery and remediation scripts. No ConfigMgr connection is made.

.NOTES
    Version: 1.0.20261125.0
#>
[CmdletBinding(DefaultParameterSetName = 'Create')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Create')]
    [string]$SiteCode,

    [Parameter(Mandatory = $true, ParameterSetName = 'Create')]
    [string]$SiteServer,

    [ValidateRange(1, 3650)]
    [int]$Days,

    [string[]]$ExcludeAccounts = @(),

    [string[]]$IncludeAccounts = @('*'),

    [ValidateSet('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder')]
    [string[]]$Scope = @('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder'),

    [Parameter(ParameterSetName = 'Create')]
    [string]$CollectionName,

    [Parameter(ParameterSetName = 'Create')]
    [ValidateRange(1, 365)]
    [int]$ScheduleDays = 7,

    [Parameter(ParameterSetName = 'Create')]
    [switch]$DetectOnly,

    [Parameter(ParameterSetName = 'Create', DontShow = $true)]
    [switch]$AssumeConnected,

    [Parameter(Mandatory = $true, ParameterSetName = 'ScriptOnly')]
    [switch]$ScriptOnly,

    [Parameter(Mandatory = $true, ParameterSetName = 'ScriptOnly')]
    [string]$OutputFolder
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'UserProfileCleanup.Engine.ps1')

function Remove-ScriptComment {
    # .SYNOPSIS
    # Removes comments and blank lines from PowerShell script text.
    #
    # .DESCRIPTION
    # Uses the PowerShell parser, so a '#' inside a string is kept. Throws when the text
    # does not parse, before and after the change. Line endings of the result are CRLF.
    #
    # .PARAMETER ScriptText
    # The script text.
    #
    # .EXAMPLE
    # Remove-ScriptComment -ScriptText "# note`r`n`$a = 1"
    #
    # # Returns '$a = 1'
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [string] The script text without comments.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ScriptText
    )

    $arrToken = $null
    $arrError = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$arrToken, [ref]$arrError)
    if ($arrError.Count -gt 0) {
        throw ('The script does not parse: {0}' -f $arrError[0].Message)
    }
    $strResult = $ScriptText
    $arrComment = @($arrToken | Where-Object { $_.Kind -eq [System.Management.Automation.Language.TokenKind]::Comment } |
            Sort-Object -Property { $_.Extent.StartOffset } -Descending)
    foreach ($objComment in $arrComment) {
        $strResult = $strResult.Remove($objComment.Extent.StartOffset, $objComment.Extent.EndOffset - $objComment.Extent.StartOffset)
    }
    $arrLine = @()
    foreach ($strLine in ($strResult -split "\r?\n")) {
        $strTrimmed = $strLine.TrimEnd()
        if ($strTrimmed.Length -gt 0) {
            $arrLine += $strTrimmed
        }
    }
    $strResult = ($arrLine -join "`r`n") + "`r`n"
    [void][System.Management.Automation.Language.Parser]::ParseInput($strResult, [ref]$arrToken, [ref]$arrError)
    if ($arrError.Count -gt 0) {
        throw ('The script does not parse after comment removal: {0}' -f $arrError[0].Message)
    }
    return $strResult
}


function New-UserProfileCleanupScriptSet {
    # .SYNOPSIS
    # Builds the names and the CI scripts for one day count.
    #
    # .DESCRIPTION
    # Reads UserProfileCleanup.Engine.ps1 from the folder of this script, removes its
    # comments and adds the call that uses the chosen settings. The result has the CI name,
    # the baseline name, the discovery script and the remediation script. The day count is
    # part of both names.
    #
    # .PARAMETER Days
    # Days of inactivity.
    #
    # .PARAMETER ExcludeAccounts
    # Patterns of accounts to keep.
    #
    # .PARAMETER IncludeAccounts
    # Patterns of accounts to clean.
    #
    # .PARAMETER Scope
    # Kinds of item to clean.
    #
    # .PARAMETER EnginePath
    # Full path of the engine file.
    #
    # .EXAMPLE
    # $objSet = New-UserProfileCleanupScriptSet -Days 90 -EnginePath $strEnginePath
    #
    # # $objSet.ConfigurationItemName is 'Maintenance: User Profile Cleanup - 90 Days'.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [pscustomobject] with ConfigurationItemName, BaselineName, DiscoveryScript and
    # RemediationScript.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 3650)]
        [int]$Days,
        [string[]]$ExcludeAccounts = @(),
        [string[]]$IncludeAccounts = @('*'),
        [string[]]$Scope = @('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder'),
        [Parameter(Mandatory = $true)]
        [string]$EnginePath
    )

    if (-not (Test-Path -LiteralPath $EnginePath -PathType Leaf)) {
        throw ('Engine file not found: {0}' -f $EnginePath)
    }
    $strEngine = Remove-ScriptComment -ScriptText ([System.IO.File]::ReadAllText($EnginePath))
    $strExclude = ConvertTo-SingleQuotedArray -Value $ExcludeAccounts
    $strInclude = ConvertTo-SingleQuotedArray -Value $IncludeAccounts
    $strKind = ConvertTo-SingleQuotedArray -Value $Scope
    $strQuery = "-MaxAgeDays $Days -ExcludeAccount $strExclude -IncludeAccount $strInclude -Kind $strKind"

    $strDiscovery = "`$ErrorActionPreference = 'Stop'`r`n" + $strEngine +
        "[int]@(Get-UserProfileCleanupItem $strQuery).Count`r`n"

    $strRemediation = "`$ErrorActionPreference = 'Stop'`r`n" + $strEngine + @"
`$strLogPath = Join-Path -Path `$env:windir -ChildPath 'CCM\Logs\UserProfileCleanup.log'
foreach (`$intPass in 1..2) {
    `$arrItem = @(Get-UserProfileCleanupItem $strQuery)
    Write-UserProfileCleanupLog -LogPath `$strLogPath -Level INFO -Message ('Pass {0}: {1} item(s), inactivity limit $Days days' -f `$intPass, `$arrItem.Count)
    if (`$arrItem.Count -eq 0) {
        break
    }
    `$arrItem | Remove-UserProfileCleanupItem -LogPath `$strLogPath -Confirm:`$false | Out-Null
}

"@
    $strRemediation = $strRemediation -replace "(?<!\r)\n", "`r`n"

    foreach ($strScriptText in @($strDiscovery, $strRemediation)) {
        $arrParseError = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($strScriptText, [ref]$null, [ref]$arrParseError)
        if ($arrParseError.Count -gt 0) {
            throw ('The generated script does not parse: {0}' -f $arrParseError[0].Message)
        }
    }

    return [pscustomobject]@{
        ConfigurationItemName = ('Maintenance: User Profile Cleanup - {0} Days' -f $Days)
        BaselineName = ('Maintenance User Profile Cleanup - {0} Days' -f $Days)
        DiscoveryScript = $strDiscovery
        RemediationScript = $strRemediation
    }
}


if (-not $PSBoundParameters.ContainsKey('Days')) {
    $Days = Read-InactivityDayCount
}

$strEnginePath = Join-Path -Path $PSScriptRoot -ChildPath 'UserProfileCleanup.Engine.ps1'
$objScriptSet = New-UserProfileCleanupScriptSet -Days $Days -ExcludeAccounts $ExcludeAccounts `
    -IncludeAccounts $IncludeAccounts -Scope $Scope -EnginePath $strEnginePath
$strCIName = $objScriptSet.ConfigurationItemName
$strCBName = $objScriptSet.BaselineName
$strSettingName = 'UserProfileCleanupItemCount'

if ($PSCmdlet.ParameterSetName -eq 'ScriptOnly') {
    $strFullOutput = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
    [void][System.IO.Directory]::CreateDirectory($strFullOutput)
    $strDiscoveryFile = Join-Path -Path $strFullOutput -ChildPath ('UserProfileCleanup-Discovery-{0}Days.ps1' -f $Days)
    $strRemediationFile = Join-Path -Path $strFullOutput -ChildPath ('UserProfileCleanup-Remediation-{0}Days.ps1' -f $Days)
    $objAscii = New-Object -TypeName System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText($strDiscoveryFile, $objScriptSet.DiscoveryScript, $objAscii)
    [System.IO.File]::WriteAllText($strRemediationFile, $objScriptSet.RemediationScript, $objAscii)
    Write-Host ("Discovery script:   {0}" -f $strDiscoveryFile)
    Write-Host ("Remediation script: {0}" -f $strRemediationFile)
    return
}

# ============================================================================
# Connect to ConfigMgr
# ============================================================================

$objOriginalLocation = Get-Location
$boolCreatedCI = $false
$boolCreatedCB = $false

if (-not $AssumeConnected) {
    if (-not (Get-Command -Name New-CMConfigurationItem -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrEmpty($env:SMS_ADMIN_UI_PATH)) {
            throw 'ConfigurationManager module not found. Run this from a machine with the ConfigMgr console installed.'
        }
        $strModulePath = Join-Path -Path (Split-Path -Path $env:SMS_ADMIN_UI_PATH -Parent) -ChildPath 'ConfigurationManager.psd1'
        if (-not (Test-Path -LiteralPath $strModulePath)) {
            throw ('ConfigurationManager module not found at {0}.' -f $strModulePath)
        }
        Import-Module -Name $strModulePath
    }

    if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
        [void](New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer)
    }
    Set-Location -LiteralPath ('{0}:' -f $SiteCode)
}

try {
    if (Get-CMConfigurationItem -Name $strCIName -Fast -ErrorAction SilentlyContinue) {
        throw ("Configuration Item '{0}' already exists. Remove it first or choose another day count." -f $strCIName)
    }
    if (Get-CMBaseline -Name $strCBName -Fast -ErrorAction SilentlyContinue) {
        throw ("Configuration Baseline '{0}' already exists. Remove it first or choose another day count." -f $strCBName)
    }

    $strModeText = 'Detect + remediate'
    if ($DetectOnly) {
        $strModeText = 'Detect only'
    }

    # ========================================================================
    # Create Configuration Item
    # ========================================================================

    Write-Host ("Creating Configuration Item: {0}" -f $strCIName)
    $objCI = New-CMConfigurationItem `
        -Name $strCIName `
        -Description ("Finds user profiles unused for {0} days or more, plus orphaned profile registrations, ProfileGuid keys and profile folders. Mode: {1}. Log: %windir%\CCM\Logs\UserProfileCleanup.log. Signed-in users, the built-in Administrator and system profiles are never touched." -f $Days, $strModeText) `
        -CreationType WindowsOS
    $boolCreatedCI = $true

    $hashtableSetting = @{
        InputObject = $objCI
        Name = $strSettingName
        Description = 'Number of user profile items that qualify for cleanup'
        DataType = 'Integer'
        DiscoveryScriptLanguage = 'PowerShell'
        DiscoveryScriptText = $objScriptSet.DiscoveryScript
        Is64Bit = $true
        ValueRule = $true
        RuleName = ('No user profile data unused for {0} days or more' -f $Days)
        RuleDescription = ('The number of qualifying items must be 0. Inactivity limit: {0} days.' -f $Days)
        ExpressionOperator = 'IsEquals'
        ExpectedValue = '0'
        NoncomplianceSeverity = 'Warning'
        ReportNoncompliance = $true
    }
    if (-not $DetectOnly) {
        $hashtableSetting['RemediationScriptLanguage'] = 'PowerShell'
        $hashtableSetting['RemediationScriptText'] = $objScriptSet.RemediationScript
        $hashtableSetting['Remediate'] = $true
    }
    Write-Host '  Adding script setting and compliance rule...'
    [void](Add-CMComplianceSettingScript @hashtableSetting)
    Write-Host '  CI created.' -ForegroundColor Green

    $objCI = Get-CMConfigurationItem -Name $strCIName -Fast

    # ========================================================================
    # Create Configuration Baseline
    # ========================================================================

    Write-Host ("Creating Configuration Baseline: {0}" -f $strCBName)
    [void](New-CMBaseline -Name $strCBName -Description ("Cleans up user profile data unused for {0} days or more. Mode: {1}." -f $Days, $strModeText))
    $boolCreatedCB = $true
    [void](Set-CMBaseline -Name $strCBName -AddOSConfigurationItem $objCI.CI_ID)
    Write-Host '  Baseline created.' -ForegroundColor Green

    # ========================================================================
    # Deploy (optional)
    # ========================================================================

    if ($CollectionName) {
        Write-Host ("Deploying baseline to: {0}" -f $CollectionName)
        $objSchedule = New-CMSchedule -RecurInterval Days -RecurCount $ScheduleDays
        [void](New-CMBaselineDeployment `
                -Name $strCBName -CollectionName $CollectionName `
                -EnableEnforcement (-not $DetectOnly) -OverrideServiceWindow $false `
                -GenerateAlert $false -MonitoredByScom $false -Schedule $objSchedule)
        Write-Host ("  Deployed every {0} day(s), mode: {1}" -f $ScheduleDays, $strModeText) -ForegroundColor Green
    } else {
        Write-Host '  Baseline created but NOT deployed. Re-run with -CollectionName, or deploy it from the console.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '=== Summary ===' -ForegroundColor Cyan
    Write-Host ("CI:         {0}" -f $strCIName)
    Write-Host ("Baseline:   {0}" -f $strCBName)
    Write-Host ("Days:       {0}" -f $Days)
    Write-Host ("Scope:      {0}" -f ($Scope -join ', '))
    Write-Host ("Exclude:    {0}" -f (@($ExcludeAccounts) -join ', '))
    Write-Host ("Include:    {0}" -f (@($IncludeAccounts) -join ', '))
    Write-Host ("Mode:       {0}" -f $strModeText)
    Write-Host 'Client log: %windir%\CCM\Logs\UserProfileCleanup.log'
} catch {
    # All or nothing: a failed run removes what it created, so the next run is not blocked by
    # the "already exists" check.
    Write-Warning ('Creation failed: {0}' -f $_.Exception.Message)
    if ($boolCreatedCB) {
        try {
            Remove-CMBaseline -Name $strCBName -Force -ErrorAction Stop
        } catch {
            Write-Warning ("Baseline '{0}' was not removed: {1}" -f $strCBName, $_.Exception.Message)
        }
    }
    if ($boolCreatedCI) {
        try {
            Remove-CMConfigurationItem -Name $strCIName -Force -ErrorAction Stop
        } catch {
            Write-Warning ("Configuration Item '{0}' was not removed: {1}" -f $strCIName, $_.Exception.Message)
        }
    }
    throw
} finally {
    if (-not $AssumeConnected) {
        Set-Location -LiteralPath $objOriginalLocation
    }
}
