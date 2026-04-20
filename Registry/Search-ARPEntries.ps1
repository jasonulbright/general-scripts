<#
.SYNOPSIS
    Searches Add/Remove Programs (ARP) registry entries by DisplayName, version, and publisher.

.DESCRIPTION
    Searches HKLM Uninstall (x64 and x86) and HKCR Installer\Products for
    matching application entries. Supports wildcard matching with AND logic
    across all criteria. Reports matching entries in a formatted table.

.PARAMETER DisplayName
    Wildcard pattern to match against DisplayName. Required.

.PARAMETER DisplayVersion
    Wildcard pattern to match against DisplayVersion. Optional.

.PARAMETER Publisher
    Wildcard pattern to match against Publisher. Optional.

.EXAMPLE
    .\Search-ARPEntries.ps1 -DisplayName "*7-Zip*"
    Finds all ARP entries containing "7-Zip".

.EXAMPLE
    .\Search-ARPEntries.ps1 -DisplayName "*Microsoft*" -Publisher "*Microsoft*"
    Finds Microsoft apps published by Microsoft.
#>
param(
    [Parameter(Mandatory)]
    [string]$DisplayName,
    [string]$DisplayVersion,
    [string]$Publisher
)

function Test-EntryMatch {
    param([string]$EntryDisplayName, [string]$EntryVersion, [string]$EntryPublisher)
    if ($EntryDisplayName -notlike $DisplayName) { return $false }
    if ($DisplayVersion -and $EntryVersion -notlike $DisplayVersion) { return $false }
    if ($Publisher -and $EntryPublisher -notlike $Publisher) { return $false }
    return $true
}

$hives = @(
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'; Label = 'HKLM x64' }
    @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'; Label = 'HKLM x86' }
)
$results = @()
foreach ($hive in $hives) {
    if (-not (Test-Path $hive.Path)) { continue }
    Get-ChildItem -Path $hive.Path -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        $name = $props.DisplayName; if (-not $name) { return }
        $version = [string]$props.DisplayVersion; $pub = [string]$props.Publisher
        if (Test-EntryMatch -EntryDisplayName $name -EntryVersion $version -EntryPublisher $pub) {
            $results += [PSCustomObject]@{
                Source      = $hive.Label
                KeyName     = $_.PSChildName
                DisplayName = $name
                Version     = $version
                Publisher   = $pub
            }
        }
    }
}

$installerPath = 'HKLM:\SOFTWARE\Classes\Installer\Products'
if (Test-Path $installerPath) {
    Get-ChildItem -Path $installerPath -ErrorAction SilentlyContinue | ForEach-Object {
        $productName = (Get-ItemProperty -Path $_.PSPath -Name ProductName -ErrorAction SilentlyContinue).ProductName
        if (-not $productName) { return }
        if ($productName -like $DisplayName) {
            $results += [PSCustomObject]@{
                Source      = 'HKCR Installer'
                KeyName     = $_.PSChildName
                DisplayName = $productName
                Version     = '--'
                Publisher   = '--'
            }
        }
    }
}

$criteria = @("DisplayName: $DisplayName")
if ($DisplayVersion) { $criteria += "DisplayVersion: $DisplayVersion" }
if ($Publisher) { $criteria += "Publisher: $Publisher" }
Write-Host "`nSearch criteria (AND):" -ForegroundColor Cyan
foreach ($c in $criteria) { Write-Host "  $c" -ForegroundColor Cyan }

if ($results.Count -eq 0) {
    Write-Host "`nNo matching entries found." -ForegroundColor Yellow
    return
}

Write-Host "`nFound $($results.Count) matching entry/entries:`n" -ForegroundColor Yellow
$results | Format-Table -Property Source, DisplayName, Version, Publisher, KeyName -AutoSize
