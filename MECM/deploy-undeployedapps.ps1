<#
.SYNOPSIS
    Create a Required Install deployment only for applications that currently
    have NO deployment anywhere.
.DESCRIPTION
    Gap-filler / catch-up pass. Iterates every CM application, skips any app
    that already has at least one deployment to any collection, and creates
    a Required Install deployment to the specified collection for the rest.
    Safe to re-run - idempotent.
.PARAMETER CollectionName
    Target device collection for newly-created deployments.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER NamePattern
    Optional regex to filter which applications to consider by
    LocalizedDisplayName. Default: all applications.
.PARAMETER RestrictCheckToThisCollection
    If set, the "already has a deployment" check is scoped to
    $CollectionName only, so apps with deployments on *other* collections
    will still be deployed here.
.EXAMPLE
    .\deploy-undeployedapps.ps1 -CollectionName 'LabTest' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
.EXAMPLE
    .\deploy-undeployedapps.ps1 -CollectionName 'LabTest' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com' -RestrictCheckToThisCollection
#>
param(
    [Parameter(Mandatory)][string]$CollectionName,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider,
    [string]$NamePattern,
    [switch]$RestrictCheckToThisCollection
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
    $coll = Get-CMDeviceCollection -Name $CollectionName -ErrorAction SilentlyContinue
    if (-not $coll) { throw "Collection '$CollectionName' not found." }

    $apps = Get-CMApplication -Fast | Sort-Object LocalizedDisplayName
    if ($NamePattern) {
        $apps = $apps | Where-Object { $_.LocalizedDisplayName -match $NamePattern }
    }

    $now = Get-Date
    $new = 0; $skipped = 0; $fail = 0

    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName

        if ($RestrictCheckToThisCollection) {
            $existing = Get-CMApplicationDeployment -Name $name -CollectionName $CollectionName -ErrorAction SilentlyContinue
        } else {
            $existing = Get-CMApplicationDeployment -Name $name -ErrorAction SilentlyContinue
        }

        if ($existing) {
            Write-Host ("[SKIP] {0} -- {1} deployment(s) already exist" -f $name, @($existing).Count) -ForegroundColor DarkGray
            $skipped++
            continue
        }

        try {
            New-CMApplicationDeployment -Name $name -CollectionName $CollectionName `
                -DeployPurpose Required -DeployAction Install `
                -AvailableDateTime $now -DeadlineDateTime $now -TimeBaseOn LocalTime `
                -UserNotification DisplayAll `
                -OverrideServiceWindow $true -RebootOutsideServiceWindow $true `
                -ErrorAction Stop | Out-Null
            Write-Host ("[NEW]  {0}" -f $name)
            $new++
        }
        catch {
            Write-Host ("[FAIL] {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }
    Write-Host ("`nSummary: {0} new deployments, {1} skipped, {2} failed" -f $new, $skipped, $fail)
}
finally {
    Set-Location $originalLocation
}
