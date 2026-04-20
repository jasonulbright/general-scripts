<#
.SYNOPSIS
    Remove every CM application in the site. Refuses if any deployments remain.
.DESCRIPTION
    Bulk-removes every Configuration Manager application. Will refuse to run
    if any application still has a deployment - deployments must be removed
    first via remove-alldeployments.ps1. Also removes content distribution
    implicitly (Remove-CMApplication deletes content records with the app).

    Destructive and site-wide. Intended for lab teardown, not production.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER Force
    Skip the interactive "YES" confirmation. Required for non-interactive /
    scripted use (e.g., when wrapping in Invoke-Command).
.EXAMPLE
    .\remove-allapps.ps1 -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
.EXAMPLE
    # Sequenced lab reset:
    .\remove-alldeployments.ps1 -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com' -Force
    .\remove-allapps.ps1        -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com' -Force
#>
param(
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider,
    [switch]$Force
)

$modulePath = Join-Path (Split-Path $env:SMS_ADMIN_UI_PATH -Parent) "ConfigurationManager.psd1"
if (-not (Get-Module ConfigurationManager)) {
    Import-Module $modulePath -ErrorAction Stop
}

if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SMSProvider -ErrorAction Stop | Out-Null
}

$originalLocation = Get-Location
Set-Location "${SiteCode}:\"

try {
    $apps = Get-CMApplication -Fast | Sort-Object LocalizedDisplayName
    if (-not $apps -or $apps.Count -eq 0) {
        Write-Host "No applications found in the site." -ForegroundColor Yellow
        return
    }

    # Safety: refuse to remove apps while deployments still exist.
    $stillDeployed = @()
    foreach ($app in $apps) {
        $deps = Get-CMApplicationDeployment -Name $app.LocalizedDisplayName -ErrorAction SilentlyContinue
        if ($deps) {
            $stillDeployed += [pscustomobject]@{ App = $app.LocalizedDisplayName; Count = @($deps).Count }
        }
    }
    if ($stillDeployed.Count -gt 0) {
        Write-Host ("{0} application(s) still have deployments. Run remove-alldeployments.ps1 first." -f $stillDeployed.Count) -ForegroundColor Red
        foreach ($row in $stillDeployed) {
            Write-Host ("  - {0} ({1} deployment(s))" -f $row.App, $row.Count) -ForegroundColor Red
        }
        return
    }

    Write-Host ("Found {0} applications ready to remove." -f $apps.Count) -ForegroundColor Cyan

    if (-not $Force) {
        Write-Host ""
        Write-Host "This will DELETE every application in the site. Irreversible." -ForegroundColor Yellow
        $confirm = Read-Host "Type YES to proceed"
        if ($confirm -ne 'YES') {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    $ok = 0; $fail = 0
    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName
        try {
            Remove-CMApplication -Name $name -Force -ErrorAction Stop
            Write-Host ("[OK]   {0}" -f $name)
            $ok++
        }
        catch {
            Write-Host ("[FAIL] {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }

    Write-Host ("`nSummary: {0} removed, {1} failed" -f $ok, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Yellow' })
}
finally {
    Set-Location $originalLocation
}
