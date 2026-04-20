<#
.SYNOPSIS
    Remove every deployment of pattern-matched applications on a target
    collection, without recreating any new deployment.
.DESCRIPTION
    Useful mid-test when conflicts need clearing before re-deploying. Any
    app whose LocalizedDisplayName matches $NamePattern has all of its
    deployments on $CollectionName removed. Apps that have no deployment on
    the collection are reported as [NONE] and skipped.
.PARAMETER CollectionName
    Target device collection.
.PARAMETER NamePattern
    Regex matched against LocalizedDisplayName to select apps.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.EXAMPLE
    .\remove-deploymentsbypattern.ps1 -CollectionName 'LabTest' -NamePattern '^M365 (Apps for Enterprise|Project|Visio)' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
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

    $removed = 0; $none = 0; $fail = 0

    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName
        try {
            $existing = Get-CMApplicationDeployment -Name $name -CollectionName $CollectionName -ErrorAction SilentlyContinue
            if (-not $existing) {
                Write-Host ("[NONE]   {0}" -f $name) -ForegroundColor DarkGray
                $none++
                continue
            }
            foreach ($d in @($existing)) {
                Remove-CMApplicationDeployment -InputObject $d -Force -ErrorAction Stop
                Write-Host ("[REMOVE] {0}" -f $name)
                $removed++
            }
        }
        catch {
            Write-Host ("[FAIL]   {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }
    Write-Host ("`nSummary: {0} removed, {1} had no deployment, {2} failed" -f $removed, $none, $fail)
}
finally {
    Set-Location $originalLocation
}
