#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Removes orphaned or corrupt application registry entries from Uninstall and
    Installer hives when the original MSI source is missing.

.DESCRIPTION
    Searches HKLM Uninstall (x64 + WOW6432Node) and HKCR\Installer\Products for
    entries matching ALL provided criteria (AND logic across fields). Displays
    matches for review, then removes after confirmation.

    For HKLM Uninstall, each parameter matches its corresponding field.
    For HKCR Installer\Products (which only stores ProductName), all parameters
    are matched as wildcards against ProductName since version and publisher info
    are typically embedded in the name (e.g. "*Visual C++*" AND "*14.50*").

    Use this when:
      - An app's MSI source is gone (ProgramData\Package Cache deleted)
      - Uninstall left behind registry entries blocking reinstall/upgrade
      - Windows Installer thinks a product is installed but repair fails

.PARAMETER DisplayName
    Wildcard pattern to match against DisplayName/ProductName. Required.

.PARAMETER DisplayVersion
    Wildcard pattern to match against DisplayVersion. Optional, AND with other criteria.

.PARAMETER Publisher
    Wildcard pattern to match against Publisher. Optional, AND with other criteria.

.PARAMETER Force
    Skip confirmation prompt and remove immediately.

.PARAMETER WhatIf
    Show what would be removed without making changes.

.EXAMPLE
    .\Remove-AppRegistryEntries.ps1 -DisplayName '*Visual C++*' -DisplayVersion '*14.42*'
    Finds and removes all MSVC 14.42 runtime entries.

.EXAMPLE
    .\Remove-AppRegistryEntries.ps1 -DisplayName '*Acrobat*' -Publisher '*Adobe*' -WhatIf
    Preview what Adobe Acrobat entries would be removed.

.EXAMPLE
    .\Remove-AppRegistryEntries.ps1 -DisplayName '*Java*' -DisplayVersion '*8.0*' -Publisher '*Oracle*' -Force
    Remove all Oracle Java 8.0 entries without confirmation.
#>
param(
    [Parameter(Mandatory)]
    [string]$DisplayName,
    [string]$DisplayVersion,
    [string]$Publisher,
    [switch]$Force,
    [switch]$WhatIf
)

# ---------------------------------------------------------------------------
# Search functions
# ---------------------------------------------------------------------------

function Test-EntryMatch {
    <#
    .SYNOPSIS
        Tests if a registry entry matches all provided criteria (AND logic).
    #>
    param(
        [string]$EntryDisplayName,
        [string]$EntryVersion,
        [string]$EntryPublisher
    )

    if ($EntryDisplayName -notlike $DisplayName) { return $false }
    if ($DisplayVersion -and $EntryVersion -notlike $DisplayVersion) { return $false }
    if ($Publisher -and $EntryPublisher -notlike $Publisher) { return $false }

    return $true
}

function Find-UninstallEntries {
    <#
    .SYNOPSIS
        Searches HKLM Uninstall hives (x64 + WOW6432Node) for matching entries.
    #>
    $hives = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Label = 'HKLM Uninstall (x64)' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Label = 'HKLM Uninstall (x86)' }
    )

    $results = @()

    foreach ($hive in $hives) {
        if (-not (Test-Path $hive.Path)) { continue }

        Get-ChildItem -Path $hive.Path -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            $name = $props.DisplayName
            if (-not $name) { return }

            $version = [string]$props.DisplayVersion
            $pub = [string]$props.Publisher

            if (Test-EntryMatch -EntryDisplayName $name -EntryVersion $version -EntryPublisher $pub) {
                $results += [PSCustomObject]@{
                    Source      = $hive.Label
                    KeyName     = $_.PSChildName
                    DisplayName = $name
                    Version     = $version
                    Publisher   = $pub
                    RegPath     = $_.PSPath
                }
            }
        }
    }

    return $results
}

function Find-InstallerProductEntries {
    <#
    .SYNOPSIS
        Searches HKCR\Installer\Products for matching entries by ProductName.
    .DESCRIPTION
        Installer\Products only stores ProductName (no separate version or publisher
        fields). All filter parameters are applied as wildcard matches against the
        ProductName string, since version and publisher info are typically embedded
        in the name (e.g. "Microsoft Visual C++ 2022 X64 Additional Runtime - 14.50.35719").
    #>
    $installerPath = 'HKLM:\SOFTWARE\Classes\Installer\Products'
    if (-not (Test-Path $installerPath)) { return @() }

    $results = @()

    Get-ChildItem -Path $installerPath -ErrorAction SilentlyContinue | ForEach-Object {
        $productName = (Get-ItemProperty -Path $_.PSPath -Name ProductName -ErrorAction SilentlyContinue).ProductName
        if (-not $productName) { return }

        if ($productName -notlike $DisplayName) { return }
        if ($DisplayVersion -and $productName -notlike $DisplayVersion) { return }
        if ($Publisher -and $productName -notlike $Publisher) { return }

        $results += [PSCustomObject]@{
            Source      = 'HKCR Installer\Products'
            KeyName     = $_.PSChildName
            DisplayName = $productName
            Version     = '--'
            Publisher   = '--'
            RegPath     = $_.PSPath
        }
    }

    return $results
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# Build criteria display
$criteria = @("DisplayName: $DisplayName")
if ($DisplayVersion) { $criteria += "DisplayVersion: $DisplayVersion" }
if ($Publisher) { $criteria += "Publisher: $Publisher" }

Write-Host "`nSearch criteria (AND):" -ForegroundColor Cyan
foreach ($c in $criteria) { Write-Host "  $c" -ForegroundColor Cyan }
Write-Host "`nScanning registry..." -ForegroundColor Gray

$uninstallMatches = Find-UninstallEntries
$installerMatches = Find-InstallerProductEntries
$allMatches = @($uninstallMatches) + @($installerMatches)

if ($allMatches.Count -eq 0) {
    Write-Host "`nNo matching entries found." -ForegroundColor Yellow
    exit 0
}

# Display results
Write-Host "`nFound $($allMatches.Count) matching entry/entries:`n" -ForegroundColor Yellow
Write-Host ("{0,-3} {1,-28} {2,-44} {3,-14} {4}" -f "#", "Source", "Display Name", "Version", "Publisher")
Write-Host ("{0,-3} {1,-28} {2,-44} {3,-14} {4}" -f "--", "------", "------------", "-------", "---------")

$i = 0
foreach ($m in $allMatches) {
    $i++
    $name = if ($m.DisplayName.Length -gt 42) { $m.DisplayName.Substring(0, 39) + '...' } else { $m.DisplayName }
    $pub  = if ($m.Publisher.Length -gt 25) { $m.Publisher.Substring(0, 22) + '...' } else { $m.Publisher }
    Write-Host ("{0,-3} {1,-28} {2,-44} {3,-14} {4}" -f $i, $m.Source, $name, $m.Version, $pub)
}

Write-Host "`nRegistry paths:" -ForegroundColor Gray
foreach ($m in $allMatches) {
    Write-Host "  $($m.RegPath)" -ForegroundColor DarkGray
}

if ($WhatIf) {
    Write-Host "`n[WhatIf] Would remove $($allMatches.Count) entry/entries. No changes made." -ForegroundColor Cyan
    exit 0
}

# Confirm
if (-not $Force) {
    Write-Host ""
    $confirm = Read-Host "Remove all $($allMatches.Count) entries? (YES to confirm)"
    if ($confirm -ne 'YES') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Remove
Write-Host ""
$removed = 0
$failed = 0

foreach ($m in $allMatches) {
    try {
        Remove-Item -Path $m.RegPath -Recurse -Force -ErrorAction Stop
        Write-Host "  Removed: $($m.DisplayName) [$($m.Source)]" -ForegroundColor Green
        $removed++
    }
    catch {
        Write-Host "  FAILED:  $($m.DisplayName) - $_" -ForegroundColor Red
        $failed++
    }
}

$color = if ($failed -eq 0) { 'Green' } else { 'Yellow' }
Write-Host "`nDone. Removed: $removed, Failed: $failed" -ForegroundColor $color

if ($removed -gt 0) {
    Write-Host "`nNote: You may need to restart Windows Installer service or reboot" -ForegroundColor Gray
    Write-Host "before reinstalling the application." -ForegroundColor Gray
}
