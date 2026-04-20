<#
.SYNOPSIS
    Remove every application deployment in the site (all apps, all collections).
.DESCRIPTION
    Iterates every CM application and removes every deployment attached to it,
    regardless of target collection. Destructive and site-wide. Intended for
    lab teardown prior to re-seeding, not production.

    Pair with remove-allapps.ps1 when you want a full reset - run this first,
    then remove-allapps.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER Force
    Skip the interactive "YES" confirmation. Required for non-interactive /
    scripted use (e.g., when wrapping in Invoke-Command).
.EXAMPLE
    .\remove-alldeployments.ps1 -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
.EXAMPLE
    # Non-interactive: wrap in Invoke-Command with -Force
    Invoke-Command -ComputerName CM01 -Credential $cred -ScriptBlock {
        & 'c:\scripts\remove-alldeployments.ps1' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com' -Force
    }
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

    # First pass: enumerate what will be removed so the user can see scope.
    $allDeployments = @()
    foreach ($app in $apps) {
        $deps = Get-CMApplicationDeployment -Name $app.LocalizedDisplayName -ErrorAction SilentlyContinue
        foreach ($d in @($deps)) {
            $allDeployments += [pscustomobject]@{
                App        = $app.LocalizedDisplayName
                Collection = $d.CollectionName
                Purpose    = if ($d.OfferTypeID -eq 0) { 'Required' } else { 'Available' }
                Deployment = $d
            }
        }
    }

    $total = $allDeployments.Count
    if ($total -eq 0) {
        Write-Host "No deployments found; nothing to remove." -ForegroundColor Yellow
        return
    }

    Write-Host ("Found {0} deployments across {1} applications." -f $total, $apps.Count) -ForegroundColor Cyan

    if (-not $Force) {
        Write-Host ""
        Write-Host "This will DELETE every deployment in the site. Irreversible." -ForegroundColor Yellow
        $confirm = Read-Host "Type YES to proceed"
        if ($confirm -ne 'YES') {
            Write-Host "Cancelled." -ForegroundColor Yellow
            return
        }
    }

    $ok = 0; $fail = 0
    foreach ($row in $allDeployments) {
        try {
            Remove-CMApplicationDeployment -InputObject $row.Deployment -Force -ErrorAction Stop
            Write-Host ("[OK]   {0} -> {1} ({2})" -f $row.App, $row.Collection, $row.Purpose)
            $ok++
        }
        catch {
            Write-Host ("[FAIL] {0} -> {1} -- {2}" -f $row.App, $row.Collection, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }

    Write-Host ("`nSummary: {0} removed, {1} failed" -f $ok, $fail) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Yellow' })
}
finally {
    Set-Location $originalLocation
}
