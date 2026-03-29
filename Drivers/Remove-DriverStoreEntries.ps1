<#
.SYNOPSIS
    Removes stubborn drivers from the Windows driver store by name pattern.

.DESCRIPTION
    Enumerates the driver store via pnputil, finds drivers whose Original Name
    matches the specified pattern, force-removes them, then deletes their
    FileRepository folders (taking ownership if necessary).

    Useful for removing bloatware drivers that persist through conventional
    uninstall methods. The default pattern targets Alienware Command Center
    (AWCC/ACCC), which is known to reinstall itself via Windows Update driver
    delivery, creating a recurring toast notification loop prompting the user
    to install or update AWCC. Removing the driver store entries and their
    FileRepository folders breaks this cycle permanently.

.PARAMETER Pattern
    Regex pattern to match against the Original Name in pnputil output.
    Default: "awcc|accc" (Alienware Command Center).

.EXAMPLE
    .\Remove-DriverStoreEntries.ps1
    Removes all AWCC/ACCC drivers.

.EXAMPLE
    .\Remove-DriverStoreEntries.ps1 -Pattern "nahimic|a-volute"
    Removes Nahimic audio drivers.

.EXAMPLE
    .\Remove-DriverStoreEntries.ps1 -Pattern "realtek" -WhatIf
    Shows what would be removed without actually removing.
#>
#Requires -RunAsAdministrator
param(
    [string]$Pattern = 'awcc|accc',
    [switch]$WhatIf
)

Write-Host "=== Enumerating drivers matching '$Pattern' ===" -ForegroundColor Cyan

$oemInfs = pnputil /enum-drivers 2>&1
$lines = $oemInfs -split "`n"
$currentOem = ''
$removed = @()

foreach ($line in $lines) {
    if ($line -match 'Published Name\s*:\s*(oem\d+\.inf)') {
        $currentOem = $Matches[1]
    }
    if ($line -match "Original Name\s*:\s*.*($Pattern).*\.inf" -and $currentOem) {
        Write-Host "  Found: $currentOem -> $($line.Trim())" -ForegroundColor Yellow
        if ($WhatIf) {
            Write-Host "  WhatIf: Would remove $currentOem" -ForegroundColor DarkGray
        } else {
            Write-Host "  Removing from driver store..." -ForegroundColor Yellow
            $result = pnputil /delete-driver $currentOem /force 2>&1
            Write-Host "  $result"
        }
        $removed += $currentOem
        $currentOem = ''
    }
}

if ($removed.Count -eq 0) {
    Write-Host "  No drivers found matching '$Pattern'" -ForegroundColor Green
}

Write-Host "`n=== FileRepository folders ===" -ForegroundColor Cyan

$repo = 'C:\Windows\System32\DriverStore\FileRepository'
$folders = Get-ChildItem $repo -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $Pattern }

foreach ($folder in $folders) {
    Write-Host "  $($folder.Name)" -ForegroundColor Yellow

    if ($WhatIf) {
        Write-Host "  WhatIf: Would delete $($folder.FullName)" -ForegroundColor DarkGray
        continue
    }

    takeown /F $folder.FullName /R /D Y 2>&1 | Out-Null
    icacls $folder.FullName /grant "${env:USERNAME}:(OI)(CI)F" /T /Q 2>&1 | Out-Null

    try {
        Remove-Item $folder.FullName -Recurse -Force -ErrorAction Stop
        Write-Host "  Deleted" -ForegroundColor Green
    }
    catch {
        Write-Host "  Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$action = if ($WhatIf) { "would be removed" } else { "removed" }
Write-Host "`n$($removed.Count) driver(s) $action, $($folders.Count) folder(s) $action."
