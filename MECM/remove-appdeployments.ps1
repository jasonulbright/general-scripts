<#
.SYNOPSIS
    Remove all deployments for a specific MECM application.
.DESCRIPTION
    Queries all deployments for the given application name, displays them
    for review, then removes them after confirmation.
.PARAMETER ApplicationName
    Exact application name as shown in the MECM console.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER Force
    Skip confirmation prompt and remove immediately.
.PARAMETER WhatIf
    Show what would be removed without actually removing.
.EXAMPLE
    .\remove-appdeployments.ps1 -ApplicationName "VMware Tools 13.0.5" -SiteCode "PS1" -SMSProvider "sccm01.contoso.com" -Force
#>
param(
    [Parameter(Mandatory)][string]$ApplicationName,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider,
    [switch]$Force,
    [switch]$WhatIf
)

# Connect to CM
$modulePath = Join-Path (Split-Path $env:SMS_ADMIN_UI_PATH -Parent) "ConfigurationManager.psd1"
if (-not (Get-Module ConfigurationManager)) {
    Import-Module $modulePath -ErrorAction Stop
}

$drive = Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue
if (-not $drive) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SMSProvider -ErrorAction Stop | Out-Null
}

$originalLocation = Get-Location
Set-Location "${SiteCode}:\"

try {
    # Verify app exists
    $app = Get-CMApplication -Name $ApplicationName -ErrorAction SilentlyContinue
    if (-not $app) {
        Write-Host "`nApplication not found: $ApplicationName" -ForegroundColor Red
        return
    }

    Write-Host "`nApplication: $($app.LocalizedDisplayName) v$($app.SoftwareVersion)" -ForegroundColor Cyan

    # Get all deployments
    $deployments = Get-CMApplicationDeployment -Name $ApplicationName -ErrorAction Stop
    if (-not $deployments -or $deployments.Count -eq 0) {
        Write-Host "No deployments found for this application." -ForegroundColor Yellow
        return
    }

    # Display all deployments
    Write-Host "`nFound $($deployments.Count) deployment(s):`n" -ForegroundColor Yellow
    Write-Host ("{0,-4} {1,-40} {2,-12} {3,-20}" -f "#", "Collection", "Purpose", "Created")
    Write-Host ("{0,-4} {1,-40} {2,-12} {3,-20}" -f "--", "----------", "-------", "-------")

    $i = 0
    foreach ($d in $deployments) {
        $i++
        $purpose = if ($d.OfferTypeID -eq 0) { 'Required' } else { 'Available' }
        $created = $d.CreationTime.ToString('yyyy-MM-dd HH:mm')
        Write-Host ("{0,-4} {1,-40} {2,-12} {3,-20}" -f $i, $d.CollectionName, $purpose, $created)
    }

    if ($WhatIf) {
        Write-Host "`n[WhatIf] Would remove $($deployments.Count) deployment(s). No changes made." -ForegroundColor Cyan
        return
    }

    # Confirm (skip if -Force)
    if (-not $Force) {
        Write-Host ""
        $confirm = Read-Host "Remove all $($deployments.Count) deployments? (YES to confirm)"
        if ($confirm -ne 'YES') {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    # Remove
    Write-Host ""
    $removed = 0
    $failed = 0
    foreach ($d in $deployments) {
        try {
            Remove-CMApplicationDeployment -InputObject $d -Force -ErrorAction Stop
            Write-Host "  Removed: $($d.CollectionName)" -ForegroundColor Green
            $removed++
        }
        catch {
            Write-Host "  FAILED:  $($d.CollectionName) - $_" -ForegroundColor Red
            $failed++
        }
    }

    Write-Host "`nDone. Removed: $removed, Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
}
finally {
    Set-Location $originalLocation
}
