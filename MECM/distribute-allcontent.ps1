<#
.SYNOPSIS
    Distribute content for every MECM application to a distribution point group.
.DESCRIPTION
    Iterates every CM application returned by Get-CMApplication and invokes
    Start-CMContentDistribution to the specified DP group. Treats "has
    already been targeted" as a non-error (idempotent re-run).
.PARAMETER DistributionPointGroupName
    Name of the DP group to distribute content to.
.PARAMETER SiteCode
    3-character MECM site code.
.PARAMETER SMSProvider
    SMS Provider server hostname.
.PARAMETER NamePattern
    Optional regex to filter which applications to distribute by
    LocalizedDisplayName. Default: distribute all.
.EXAMPLE
    .\distribute-allcontent.ps1 -DistributionPointGroupName 'All DPs' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com'
.EXAMPLE
    .\distribute-allcontent.ps1 -DistributionPointGroupName 'All DPs' -SiteCode 'PS1' -SMSProvider 'sccm01.contoso.com' -NamePattern '^M365 '
#>
param(
    [Parameter(Mandatory)][string]$DistributionPointGroupName,
    [Parameter(Mandatory)][string]$SiteCode,
    [Parameter(Mandatory)][string]$SMSProvider,
    [string]$NamePattern
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
    if ($NamePattern) {
        $apps = $apps | Where-Object { $_.LocalizedDisplayName -match $NamePattern }
    }

    $ok = 0; $already = 0; $fail = 0
    foreach ($app in $apps) {
        $name = $app.LocalizedDisplayName
        try {
            Start-CMContentDistribution -ApplicationName $name -DistributionPointGroupName $DistributionPointGroupName -ErrorAction Stop
            Write-Host ("[OK]      {0}" -f $name); $ok++
        }
        catch {
            if ($_.Exception.Message -match 'already been targeted') {
                Write-Host ("[ALREADY] {0}" -f $name); $already++
            }
            else {
                Write-Host ("[FAIL]    {0} -- {1}" -f $name, $_.Exception.Message) -ForegroundColor Red
                $fail++
            }
        }
    }
    Write-Host ("`nSummary: {0} distributed, {1} already targeted, {2} failed" -f $ok, $already, $fail)
}
finally {
    Set-Location $originalLocation
}
