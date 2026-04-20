<#
.SYNOPSIS
    Convert every Install deployment on a collection to an Uninstall
    deployment, except apps matching a keep-installed regex.
.DESCRIPTION
    Second-pass script for cleaning up a lab test client. Removes any
    existing deployment of each app on the target collection, then creates
    a Required Uninstall deployment for that app - unless the app name
    matches $KeepInstalledPattern, in which case the current Install
    deployment is left alone. Typical keep-installed list is the
    workstation baseline (runtimes, archivers, text editors, drivers)
    whose removal would break subsequent test runs.
.PARAMETER CollectionName
    Target device collection whose deployments are being switched.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER KeepInstalledPattern
    Regex matched against LocalizedDisplayName. Apps matching this pattern
    keep their current Install deployment and get no uninstall deployment
    created. Default: match nothing (every app is uninstalled).
.EXAMPLE
    .\switch-deploymentstouninstall.ps1 -CollectionName 'LabTest' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com' -KeepInstalledPattern '^(7-Zip|Notepad\+\+|Microsoft Visual C\+\+|Microsoft Windows Desktop Runtime|Microsoft Edge WebView2 Runtime|Microsoft ODBC Driver|Microsoft OLE DB Driver)'
#>
param(
    [Parameter(Mandatory)][string]$CollectionName,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider,
    [string]$KeepInstalledPattern = '(?!x)x'  # matches nothing by default
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
    $now  = Get-Date
    $removed = 0; $kept = 0; $uninstalled = 0; $fail = 0

    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName

        if ($name -match $KeepInstalledPattern) {
            Write-Host ("[KEEP] {0}" -f $name) -ForegroundColor DarkGray
            $kept++
            continue
        }

        try {
            $existing = Get-CMApplicationDeployment -Name $name -CollectionName $CollectionName -ErrorAction SilentlyContinue
            foreach ($d in @($existing)) {
                Remove-CMApplicationDeployment -InputObject $d -Force -ErrorAction Stop
                $removed++
            }
        }
        catch {
            Write-Host ("[WARN] remove {0}: {1}" -f $name, $_.Exception.Message) -ForegroundColor Yellow
        }

        try {
            New-CMApplicationDeployment -Name $name -CollectionName $CollectionName `
                -DeployPurpose Required -DeployAction Uninstall `
                -AvailableDateTime $now -DeadlineDateTime $now -TimeBaseOn LocalTime `
                -UserNotification DisplayAll `
                -OverrideServiceWindow $true -RebootOutsideServiceWindow $true `
                -ErrorAction Stop | Out-Null
            Write-Host ("[UNINSTALL] {0}" -f $name)
            $uninstalled++
        }
        catch {
            Write-Host ("[FAIL] {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
            $fail++
        }
    }
    Write-Host ("`nSummary: {0} install deployments removed, {1} uninstall deployments created, {2} kept installed, {3} failed" -f $removed, $uninstalled, $kept, $fail)
}
finally {
    Set-Location $originalLocation
}
