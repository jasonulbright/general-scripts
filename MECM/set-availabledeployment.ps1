<#
.SYNOPSIS
    Switch a pattern-matched set of applications from any existing
    deployment to a Required-less Available deployment on the target
    collection.
.DESCRIPTION
    Generalization of the M365-specific case: ODT / Click-to-Run M365
    variants (Apps for Enterprise, Project, Visio - both x64 and x86)
    conflict on the same client because Office pins the architecture
    per-tenant. A Required install for all six fails; making them Available
    lets the user pick one via Software Center.

    Pattern: remove existing deployments of matching apps on the target
    collection, then create a Required-less Available deployment. Available
    deployments do NOT accept -DeadlineDateTime, -OverrideServiceWindow, or
    -RebootOutsideServiceWindow - MECM warns if those are passed.
.PARAMETER CollectionName
    Target device collection.
.PARAMETER NamePattern
    Regex matched against LocalizedDisplayName to select which apps to switch.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.EXAMPLE
    .\set-availabledeployment.ps1 -CollectionName 'LabTest' -NamePattern '^M365 (Apps for Enterprise|Project|Visio)' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
#>
param(
    [Parameter(Mandatory)][string]$CollectionName,
    [Parameter(Mandatory)][string]$NamePattern,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider
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

    $apps = Get-CMApplication -Fast |
        Where-Object { $_.LocalizedDisplayName -match $NamePattern } |
        Sort-Object LocalizedDisplayName

    $now = Get-Date
    $removed = 0; $created = 0; $fail = 0

    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName

        try {
            foreach ($d in @(Get-CMApplicationDeployment -Name $name -CollectionName $CollectionName -ErrorAction SilentlyContinue)) {
                Remove-CMApplicationDeployment -InputObject $d -Force -ErrorAction Stop
                $removed++
            }
        }
        catch {
            Write-Host ("[WARN] remove {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow
        }

        try {
            New-CMApplicationDeployment -Name $name -CollectionName $CollectionName `
                -DeployPurpose Available -DeployAction Install `
                -AvailableDateTime $now -TimeBaseOn LocalTime `
                -UserNotification DisplayAll `
                -ErrorAction Stop | Out-Null
            Write-Host ("[AVAIL] {0}" -f $name)
            $created++
        }
        catch {
            Write-Host ("[FAIL] {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }
    Write-Host ("`nSummary: {0} deployments removed, {1} Available deployments created, {2} failed" -f $removed, $created, $fail)
}
finally {
    Set-Location $originalLocation
}
