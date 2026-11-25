<#
.SYNOPSIS
    Creates a ConfigMgr package and program that clean up stale and orphaned user profile
    data. Use it on a recurring schedule, or as a package step in a task sequence.

.DESCRIPTION
    The package option of the profile cleanup. The Configuration Item / Baseline option is
    New-UserProfileCleanupBaseline.ps1. Both use the same engine and the same rules.

    The script:
      1. Asks for the day count (30, 60, 90 and so on) unless -Days is given.
      2. Stages the content in -SourcePath: Invoke-UserProfileCleanup.ps1,
         UserProfileCleanup.Engine.ps1 and a generated Run-UserProfileCleanup.ps1 that holds
         the chosen settings.
      3. Creates the package and one standard program. The day count is part of both names,
         for example "Maintenance: User Profile Cleanup (Package) - 90 Days".
      4. Optionally distributes the content (-DistributionPointGroupName or
         -DistributionPointName).
      5. Optionally creates a required deployment with a recurring schedule
         (-CollectionName, -ScheduleDays). The program reruns on every cycle.

    The program runs hidden, with administrative rights, whether or not a user is signed in.
    Signed-in users' profiles are loaded, so they are never removed.

    Use in a task sequence: add a Run Command Line step in the full OS (not WinPE), select this
    package, and use the command line that the script prints. Set "Continue on error" when a
    failed removal must not stop the task sequence (exit code 1 means one or more items
    could not be removed).

    -StageOnly writes the content and prints the command lines. It makes no ConfigMgr change.

.PARAMETER SiteCode
    ConfigMgr site code.

.PARAMETER SiteServer
    ConfigMgr site server FQDN (SMS Provider).

.PARAMETER SourcePath
    Folder for the package content. The site server must be able to read it, so use a UNC
    path for a real package. The script creates the folder when it is missing.

.PARAMETER Days
    Days of inactivity before a profile is cleaned up. When omitted, the script asks.

.PARAMETER ExcludeAccounts
    Wildcard patterns for accounts to keep.

.PARAMETER IncludeAccounts
    Wildcard patterns. When set, only matching accounts are cleaned. Default: '*'.

.PARAMETER Scope
    Kinds of item to clean. Default: all four.

.PARAMETER DetectOnly
    Report only. The program lists the items and removes nothing.

.PARAMETER DistributionPointGroupName
    Distribution point group that receives the content.

.PARAMETER DistributionPointName
    Distribution point (FQDN) that receives the content.

.PARAMETER CollectionName
    If specified, creates a required deployment with a recurring schedule on this collection.

.PARAMETER ScheduleDays
    The program runs every this many days. Default: 7.

.PARAMETER RunOutsideMaintenanceWindow
    Lets the required deployment run when the deadline passes even if no maintenance window is
    open. Without it the program waits for a maintenance window, as any required deployment
    does.

.PARAMETER StageOnly
    Write the content to -SourcePath and stop. No ConfigMgr connection.

.PARAMETER AssumeConnected
    For tests. Skips the module import, the site drive and the change of location.

.EXAMPLE
    .\New-UserProfileCleanupPackage.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -SourcePath \\CM01\Sources$\Packages\ProfileCleanup90

    Asks for the day count, then creates the package and program. Nothing is deployed.

.EXAMPLE
    .\New-UserProfileCleanupPackage.ps1 -SiteCode MCM -SiteServer CM01.contoso.com -SourcePath \\CM01\Sources$\Packages\ProfileCleanup90 -Days 90 -ExcludeAccounts 'svc_*' -DistributionPointGroupName 'All DPs' -CollectionName 'All Workstations' -ScheduleDays 7

    Creates the 90-day package, distributes it, and runs it every 7 days on the collection.

.EXAMPLE
    .\New-UserProfileCleanupPackage.ps1 -StageOnly -SourcePath C:\Temp\ProfileCleanup -Days 60

    Writes the content and prints the command lines for a task sequence step.

.NOTES
    Version: 1.0.20261125.0
#>
[CmdletBinding(DefaultParameterSetName = 'Create')]
param (
    [Parameter(Mandatory = $true, ParameterSetName = 'Create')]
    [string]$SiteCode,

    [Parameter(Mandatory = $true, ParameterSetName = 'Create')]
    [string]$SiteServer,

    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [ValidateRange(1, 3650)]
    [int]$Days,

    [string[]]$ExcludeAccounts = @(),

    [string[]]$IncludeAccounts = @('*'),

    [ValidateSet('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder')]
    [string[]]$Scope = @('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder'),

    [switch]$DetectOnly,

    [Parameter(ParameterSetName = 'Create')]
    [string]$DistributionPointGroupName,

    [Parameter(ParameterSetName = 'Create')]
    [string]$DistributionPointName,

    [Parameter(ParameterSetName = 'Create')]
    [string]$CollectionName,

    [Parameter(ParameterSetName = 'Create')]
    [ValidateRange(1, 365)]
    [int]$ScheduleDays = 7,

    [Parameter(ParameterSetName = 'Create')]
    [switch]$RunOutsideMaintenanceWindow,

    [Parameter(ParameterSetName = 'Create', DontShow = $true)]
    [switch]$AssumeConnected,

    [Parameter(Mandatory = $true, ParameterSetName = 'StageOnly')]
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'UserProfileCleanup.Engine.ps1')

if (-not $PSBoundParameters.ContainsKey('Days')) {
    $Days = Read-InactivityDayCount
}

$strPackageName = 'Maintenance: User Profile Cleanup (Package) - {0} Days' -f $Days
$strProgramName = 'Clean up user profiles ({0} days)' -f $Days
$strWrapperName = 'Run-UserProfileCleanup.ps1'
$strCommandLine = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\{0}' -f $strWrapperName

# ============================================================================
# Stage the content
# ============================================================================

$strFullSource = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SourcePath)
$strQuery = "-Days $Days -ExcludeAccounts {0} -IncludeAccounts {1} -Scope {2}" -f
    (ConvertTo-SingleQuotedArray -Value $ExcludeAccounts), (ConvertTo-SingleQuotedArray -Value $IncludeAccounts),
    (ConvertTo-SingleQuotedArray -Value $Scope)
if ($DetectOnly) {
    $strQuery += ' -DetectOnly'
}
$arrWrapperLine = @(
    ('# Generated by New-UserProfileCleanupPackage.ps1. Settings of the {0}-day cleanup.' -f $Days),
    '$ErrorActionPreference = ''Stop''',
    '$LASTEXITCODE = $null',
    'try {',
    ('    & (Join-Path -Path $PSScriptRoot -ChildPath ''Invoke-UserProfileCleanup.ps1'') {0}' -f $strQuery),
    '} catch {',
    '    [Console]::Error.WriteLine($_.Exception.Message)',
    '    exit 2',
    '}',
    'if ($null -eq $LASTEXITCODE) {',
    '    exit 2',
    '}',
    'exit $LASTEXITCODE'
)
$strWrapperText = ($arrWrapperLine -join "`r`n") + "`r`n"
$arrParseError = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($strWrapperText, [ref]$null, [ref]$arrParseError)
if ($arrParseError.Count -gt 0) {
    throw ('The generated wrapper does not parse: {0}' -f $arrParseError[0].Message)
}

function Write-PackageContent {
    # .SYNOPSIS
    # Writes the package content to the source folder.
    #
    # .DESCRIPTION
    # Copies the runner and the engine (an existing copy is replaced, which updates it) and
    # writes the generated wrapper. It uses .NET file calls, because Copy-Item cannot reach a UNC
    # path while the current location is the ConfigMgr site drive. Throws, and writes nothing, when the folder already holds
    # a wrapper with other settings: that folder belongs to another package, and a content
    # update of that package would ship these settings.
    #
    # .PARAMETER Folder
    # The source folder.
    #
    # .PARAMETER WrapperText
    # The text of the generated wrapper.
    #
    # .EXAMPLE
    # Write-PackageContent -Folder '\\CM01\Sources$\ProfileCleanup90' -WrapperText $strWrapperText
    #
    # # The three files are in the folder.
    #
    # .INPUTS
    # None. You can't pipe objects to this function.
    #
    # .OUTPUTS
    # [bool] $true when this call created the wrapper, $false when it only rewrote an identical one.
    #
    # .NOTES
    # PRIVATE/INTERNAL HELPER. This function is not part of the public API surface.
    #
    # Version: 1.0.20261125.0
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [Parameter(Mandatory = $true)]
        [string]$WrapperText
    )

    $strWrapperPath = Join-Path -Path $Folder -ChildPath 'Run-UserProfileCleanup.ps1'
    if ([System.IO.File]::Exists($strWrapperPath) -and ([System.IO.File]::ReadAllText($strWrapperPath) -cne $WrapperText)) {
        throw ("The folder '{0}' already holds Run-UserProfileCleanup.ps1 with other settings. Use another folder for this package, or delete that file." -f $Folder)
    }
    [void][System.IO.Directory]::CreateDirectory($Folder)
    foreach ($strFileName in @('Invoke-UserProfileCleanup.ps1', 'UserProfileCleanup.Engine.ps1')) {
        $strFrom = Join-Path -Path $PSScriptRoot -ChildPath $strFileName
        $strTo = Join-Path -Path $Folder -ChildPath $strFileName
        if (-not $strFrom.Equals($strTo, [System.StringComparison]::OrdinalIgnoreCase)) {
            if ([System.IO.File]::Exists($strTo)) {
                [System.IO.File]::SetAttributes($strTo, [System.IO.FileAttributes]::Normal)
            }
            [System.IO.File]::Copy($strFrom, $strTo, $true)
            [System.IO.File]::SetAttributes($strTo, [System.IO.FileAttributes]::Normal)
        }
    }
    $boolWrapperIsNew = -not [System.IO.File]::Exists($strWrapperPath)
    [System.IO.File]::WriteAllText($strWrapperPath, $WrapperText, (New-Object -TypeName System.Text.ASCIIEncoding))
    return $boolWrapperIsNew
}

if ($PSCmdlet.ParameterSetName -eq 'StageOnly') {
    [void](Write-PackageContent -Folder $strFullSource -WrapperText $strWrapperText)
    Write-Host ("Content staged in: {0}" -f $strFullSource)
    Write-Host ''
    Write-Host 'Command line for a package program or a task sequence Run Command Line step:'
    Write-Host ("  {0}" -f $strCommandLine)
    return
}

# ============================================================================
# Connect to ConfigMgr
# ============================================================================

$objOriginalLocation = Get-Location
$boolCreatedPackage = $false
$boolCreatingPackage = $false
$boolWrapperCreated = $false
$strPackageId = $null

if (-not $AssumeConnected) {
    if (-not (Get-Command -Name New-CMPackage -ErrorAction SilentlyContinue)) {
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
    if (Get-CMPackage -Name $strPackageName -Fast) {
        throw ("Package '{0}' already exists. Remove it first or choose another day count." -f $strPackageName)
    }
    if (-not $strFullSource.StartsWith('\\')) {
        Write-Warning ("The source path '{0}' is not a UNC path. The site server must be able to read it." -f $strFullSource)
    }
    $boolWrapperCreated = Write-PackageContent -Folder $strFullSource -WrapperText $strWrapperText
    Write-Host ("Content staged in: {0}" -f $strFullSource)

    $strModeText = 'Detect + remove'
    if ($DetectOnly) {
        $strModeText = 'Detect only'
    }

    # ========================================================================
    # Create package and program
    # ========================================================================

    Write-Host ("Creating package: {0}" -f $strPackageName)
    $boolCreatingPackage = $true
    $objPackage = (New-CMPackage -Name $strPackageName -Path $strFullSource -Version ('{0}d' -f $Days) `
            -Description ('Removes user profiles unused for {0} days or more and orphaned profile data. Mode: {1}.' -f $Days, $strModeText))
    $strPackageId = [string]$objPackage.PackageID
    $boolCreatedPackage = $true

    Write-Host ("Creating program: {0}" -f $strProgramName)
    [void](New-CMProgram -PackageName $strPackageName -StandardProgramName $strProgramName -CommandLine $strCommandLine `
            -RunType Hidden -ProgramRunType WhetherOrNotUserIsLoggedOn -RunMode RunWithAdministrativeRights `
            -DriveMode RunWithUnc -Duration 240 -UserInteraction $false)
    Write-Host '  Package and program created.' -ForegroundColor Green

    # ========================================================================
    # Distribute (optional)
    # ========================================================================

    $hashtableDistribution = @{ PackageName = $strPackageName }
    if ($DistributionPointGroupName) {
        $hashtableDistribution['DistributionPointGroupName'] = $DistributionPointGroupName
    }
    if ($DistributionPointName) {
        $hashtableDistribution['DistributionPointName'] = $DistributionPointName
    }
    if ($hashtableDistribution.Count -gt 1) {
        Write-Host 'Distributing content...'
        Start-CMContentDistribution @hashtableDistribution
        Write-Host '  Distribution started.' -ForegroundColor Green
    } else {
        Write-Host '  No distribution point given. Distribute the content before clients can run the program.' -ForegroundColor Yellow
    }

    # ========================================================================
    # Deploy (optional)
    # ========================================================================

    if ($CollectionName) {
        Write-Host ("Deploying to: {0}" -f $CollectionName)
        $objSchedule = New-CMSchedule -RecurInterval Days -RecurCount $ScheduleDays
        $hashtableDeployment = @{
            StandardProgram = $true
            PackageName = $strPackageName
            ProgramName = $strProgramName
            CollectionName = $CollectionName
            DeployPurpose = 'Required'
            Schedule = $objSchedule
            RerunBehavior = 'AlwaysRerunProgram'
            SendWakeupPacket = $false
            FastNetworkOption = 'DownloadContentFromDistributionPointAndRunLocally'
            SlowNetworkOption = 'DownloadContentFromDistributionPointAndLocally'
        }
        if ($RunOutsideMaintenanceWindow) {
            $hashtableDeployment['SoftwareInstallation'] = $true
        }
        [void](New-CMPackageDeployment @hashtableDeployment)
        Write-Host ("  Required deployment created. Runs every {0} day(s)." -f $ScheduleDays) -ForegroundColor Green
    } else {
        Write-Host '  Not deployed. Re-run with -CollectionName, or deploy the program from the console or a task sequence.' -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '=== Summary ===' -ForegroundColor Cyan
    Write-Host ("Package:      {0}" -f $strPackageName)
    Write-Host ("Program:      {0}" -f $strProgramName)
    Write-Host ("Content:      {0}" -f $strFullSource)
    Write-Host ("Days:         {0}" -f $Days)
    Write-Host ("Scope:        {0}" -f ($Scope -join ', '))
    Write-Host ("Exclude:      {0}" -f (@($ExcludeAccounts) -join ', '))
    Write-Host ("Include:      {0}" -f (@($IncludeAccounts) -join ', '))
    Write-Host ("Mode:         {0}" -f $strModeText)
    Write-Host 'Client log:   %windir%\CCM\Logs\UserProfileCleanup.log'
    Write-Host ''
    Write-Host 'Task sequence: add a Run Command Line step in the full OS, select this package, and use:'
    Write-Host ("  {0}" -f $strCommandLine)
    Write-Host 'Exit code 0 = finished, 1 = one or more items could not be removed. Set "Continue on error" if that must not stop the task sequence.'
} catch {
    # All or nothing: a failed run removes the package it created, so the next run is not
    # blocked by the "already exists" check.
    Write-Warning ('Creation failed: {0}' -f $_.Exception.Message)
    if ($boolCreatingPackage -and (-not $boolCreatedPackage) -and ($null -eq $strPackageId)) {
        # New-CMPackage can fail after it created the package. The check at the start found no
        # package of this name and this run has started to create one, so a package of this
        # name now is the one this run made.
        $objLeft = Get-CMPackage -Name $strPackageName -Fast -ErrorAction SilentlyContinue
        if ($objLeft) {
            $strPackageId = [string]$objLeft.PackageID
            $boolCreatedPackage = $true
        }
    }
    if ($boolCreatedPackage) {
        try {
            Remove-CMPackage -Id $strPackageId -Force -ErrorAction Stop
        } catch {
            Write-Warning ("Package '{0}' was not removed: {1}" -f $strPackageName, $_.Exception.Message)
        }
    }
    if ($boolWrapperCreated) {
        # The wrapper of this failed run would block a corrected re-run with other settings.
        try {
            [System.IO.File]::Delete((Join-Path -Path $strFullSource -ChildPath $strWrapperName))
        } catch {
            Write-Warning ("The staged wrapper was not removed: {0}" -f $_.Exception.Message)
        }
    }
    throw
} finally {
    if (-not $AssumeConnected) {
        Set-Location -LiteralPath $objOriginalLocation
    }
}
