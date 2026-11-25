<#
.SYNOPSIS
    Cleans up stale and orphaned user profile data on this computer. Runs from a ConfigMgr
    package program, a task sequence Run Command Line step, or by hand.

.DESCRIPTION
    Runs the profile cleanup engine (UserProfileCleanup.Engine.ps1, in the same folder) once:
    it finds profiles unused for -Days days or more, plus orphaned ProfileList keys,
    ProfileGuid keys and profile folders, and removes them. It makes two passes, because
    removing a profile can orphan its ProfileGuid key.

    Loaded profiles (signed-in users), the built-in Administrator, well-known accounts,
    system and service profiles, and every account that matches -ExcludeAccounts are never
    touched. See README.md for the full rules.

    When a 32-bit PowerShell starts this script on a 64-bit Windows (a package program does),
    the script starts the 64-bit PowerShell and returns its exit code. This keeps the
    registry and system folders unredirected.

    Every removed item is written to the log (default %windir%\CCM\Logs\UserProfileCleanup.log).

    Exit codes:
        0  The run finished. Nothing failed (or -DetectOnly was given).
        1  One or more items could not be removed. The log has the reason for each.
        2  The engine file is missing or does not load, or a pattern is not valid. (A value
           that fails parameter validation, for example -Days 0, stops PowerShell with a
           non-zero code of its own.)

.PARAMETER Days
    Days of inactivity before a profile is cleaned up, for example 30, 60 or 90.

.PARAMETER ExcludeAccounts
    Wildcard patterns for accounts to keep.

.PARAMETER IncludeAccounts
    Wildcard patterns. When set, only matching accounts are cleaned. Default: '*'.

.PARAMETER Scope
    Kinds of item to clean. Default: StaleProfile, OrphanRegistration, OrphanProfileGuid,
    OrphanFolder.

.PARAMETER DetectOnly
    Report only. Lists the items and removes nothing.

.PARAMETER LogPath
    Log file. Default: %windir%\CCM\Logs\UserProfileCleanup.log

.EXAMPLE
    .\Invoke-UserProfileCleanup.ps1 -Days 90 -DetectOnly

    Lists what a 90-day cleanup would remove.

.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& { $ErrorActionPreference='Stop'; try { .\Invoke-UserProfileCleanup.ps1 -Days 60 -ExcludeAccounts @('svc_*') } catch { exit 2 }; if ($null -eq $LASTEXITCODE) { exit 2 }; exit $LASTEXITCODE }"

    The form for a task sequence Run Command Line step with settings on the command line.
    The error handling makes a failed start return 2 instead of 0.

.NOTES
    Version: 1.0.20261125.0
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 3650)]
    [int]$Days,

    [string[]]$ExcludeAccounts = @(),

    [string[]]$IncludeAccounts = @('*'),

    [ValidateSet('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder')]
    [string[]]$Scope = @('StaleProfile', 'OrphanRegistration', 'OrphanProfileGuid', 'OrphanFolder'),

    [switch]$DetectOnly,

    [string]$LogPath = (Join-Path -Path $env:windir -ChildPath 'CCM\Logs\UserProfileCleanup.log')
)

$ErrorActionPreference = 'Stop'

$strEnginePath = Join-Path -Path $PSScriptRoot -ChildPath 'UserProfileCleanup.Engine.ps1'
if (-not (Test-Path -LiteralPath $strEnginePath -PathType Leaf)) {
    [Console]::Error.WriteLine(('Engine file not found: {0}' -f $strEnginePath))
    exit 2
}
try {
    . $strEnginePath
} catch {
    [Console]::Error.WriteLine(('The engine file did not load: {0}' -f $_.Exception.Message))
    exit 2
}

try {
    foreach ($strPattern in (@($ExcludeAccounts) + @($IncludeAccounts))) {
        [void](ConvertTo-SingleQuotedLiteral -Text $strPattern)
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 2
}

# A package program starts a 32-bit PowerShell on a 64-bit Windows. Start the 64-bit one.
# The call goes over as an encoded command, so no quoting of paths or patterns can go wrong.
if ([Environment]::Is64BitOperatingSystem -and (-not [Environment]::Is64BitProcess)) {
    try {
        $strNative = Join-Path -Path $env:windir -ChildPath 'sysnative\WindowsPowerShell\v1.0\powershell.exe'
        $strScriptLiteral = "'" + $PSCommandPath.Replace("'", "''") + "'"
        $strLogLiteral = "'" + $LogPath.Replace("'", "''") + "'"
        $strCall = '$ErrorActionPreference = ''Stop''; $LASTEXITCODE = $null; & {0} -Days {1} -ExcludeAccounts {2} -IncludeAccounts {3} -Scope {4} -LogPath {5}' -f
            $strScriptLiteral, $Days, (ConvertTo-SingleQuotedArray -Value $ExcludeAccounts),
            (ConvertTo-SingleQuotedArray -Value $IncludeAccounts), (ConvertTo-SingleQuotedArray -Value $Scope), $strLogLiteral
        if ($DetectOnly) {
            $strCall += ' -DetectOnly'
        }
        $strCall += '; if ($null -eq $LASTEXITCODE) { exit 2 }; exit $LASTEXITCODE'
        $strEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($strCall))
        & $strNative -NoProfile -ExecutionPolicy Bypass -EncodedCommand $strEncoded
        exit $LASTEXITCODE
    } catch {
        [Console]::Error.WriteLine(('The 64-bit PowerShell did not start: {0}' -f $_.Exception.Message))
        exit 2
    }
}

$intRemoved = 0
$intFailed = 0
$intFound = 0
try {
    Write-UserProfileCleanupLog -LogPath $LogPath -Level INFO -Message ('Start: limit {0} days, scope {1}, detect only {2}, 64-bit process {3}' -f $Days, ($Scope -join ','), [bool]$DetectOnly, [Environment]::Is64BitProcess)
    foreach ($intPass in 1..2) {
        $arrItem = @(Get-UserProfileCleanupItem -MaxAgeDays $Days -ExcludeAccount $ExcludeAccounts -IncludeAccount $IncludeAccounts -Kind $Scope)
        Write-UserProfileCleanupLog -LogPath $LogPath -Level INFO -Message ('Pass {0}: {1} item(s)' -f $intPass, $arrItem.Count)
        if ($intPass -eq 1) {
            $intFound = $arrItem.Count
        }
        if ($arrItem.Count -eq 0) {
            break
        }
        if ($DetectOnly) {
            foreach ($objItem in $arrItem) {
                $strLine = '{0} | {1} | {2} | age {3} days' -f $objItem.Kind, $objItem.Account, $objItem.Path, $objItem.AgeDays
                Write-UserProfileCleanupLog -LogPath $LogPath -Level INFO -Message ('Would remove: ' + $strLine)
                Write-Output $strLine
            }
            break
        }
        foreach ($objResult in @($arrItem | Remove-UserProfileCleanupItem -LogPath $LogPath -Confirm:$false)) {
            if ($objResult.Succeeded) {
                $intRemoved++
            } else {
                $intFailed++
                Write-Output ('FAILED {0} | {1} | {2}' -f $objResult.Kind, $objResult.Path, $objResult.Message)
            }
        }
    }
} catch {
    $intFailed++
    Write-UserProfileCleanupLog -LogPath $LogPath -Level ERROR -Message ('Run stopped by an error: {0}' -f $_.Exception.Message)
    Write-Output ('FAILED run stopped by an error: {0}' -f $_.Exception.Message)
}
Write-UserProfileCleanupLog -LogPath $LogPath -Level INFO -Message ('Done: found {0}, removed {1}, failed {2}' -f $intFound, $intRemoved, $intFailed)
Write-Output ('Found {0}, removed {1}, failed {2}.' -f $intFound, $intRemoved, $intFailed)
if ($intFailed -gt 0) {
    exit 1
}
exit 0
