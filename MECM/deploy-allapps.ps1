<#
.SYNOPSIS
    Create Required Install deployments for every MECM application against a
    target collection.
.DESCRIPTION
    Iterates every CM application and creates a Required Install deployment
    to the specified collection. Intended for lab / first-pass testing
    against a direct-membership collection scoped to a single test device.
    DO NOT target broad collections like 'All Systems' - doing so will
    deploy every app to the site server and DC.
.PARAMETER CollectionName
    Target device collection. Should be a direct-membership test collection
    scoped to one or a few test devices.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER NamePattern
    Optional regex to filter which applications to deploy by
    LocalizedDisplayName. Default: deploy all.
.PARAMETER DeployPurpose
    Required (default) or Available.
.EXAMPLE
    .\deploy-allapps.ps1 -CollectionName 'LabTest' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
#>
param(
    [Parameter(Mandatory)][string]$CollectionName,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider,
    [string]$NamePattern,
    [ValidateSet('Required','Available')][string]$DeployPurpose = 'Required'
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
    $ok = 0; $fail = 0
    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName
        try {
            $splat = @{
                Name              = $name
                CollectionName    = $CollectionName
                DeployPurpose     = $DeployPurpose
                DeployAction      = 'Install'
                AvailableDateTime = $now
                TimeBaseOn        = 'LocalTime'
                UserNotification  = 'DisplayAll'
                ErrorAction       = 'Stop'
            }
            if ($DeployPurpose -eq 'Required') {
                $splat['DeadlineDateTime']            = $now
                $splat['OverrideServiceWindow']       = $true
                $splat['RebootOutsideServiceWindow']  = $true
            }
            New-CMApplicationDeployment @splat | Out-Null
            Write-Host ("[OK]   {0}" -f $name); $ok++
        }
        catch {
            Write-Host ("[FAIL] {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }
    Write-Host ("`nSummary: {0} deployed, {1} failed" -f $ok, $fail)
}
finally {
    Set-Location $originalLocation
}
