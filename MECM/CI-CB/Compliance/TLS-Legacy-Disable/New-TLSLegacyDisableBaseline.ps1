<#
.SYNOPSIS
    Creates an MECM CI + Baseline that disables legacy TLS / SSL protocols and forces .NET strong crypto.

.DESCRIPTION
    24 native registry-value compliance settings on a single CI:

      SCHANNEL\Protocols (20 settings)
        SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1 - Server + Client - Enabled=0, DisabledByDefault=1
        TLS 1.2                            - Server + Client - Enabled=1, DisabledByDefault=0

      .NET Framework v4.0.30319 (4 settings)
        SchUseStrongCrypto      = 1   (HKLM + WOW6432Node)
        SystemDefaultTlsVersions = 1   (HKLM + WOW6432Node)

    No embedded scripts. MECM handles discovery, comparison, and remediation natively.

    Reboot required for SCHANNEL to reload protocol configuration.

    TLS 1.3 is intentionally out of scope (not supported on Server 2019 and earlier).

.PARAMETER SiteCode
    MECM site code.

.PARAMETER SiteServer
    MECM site server FQDN.

.PARAMETER CollectionName
    If specified, deploys the baseline to this collection daily with remediation enabled.

.PARAMETER DetectOnly
    Create the CI without remediation.

.EXAMPLE
    .\New-TLSLegacyDisableBaseline.ps1 -SiteServer CM01.contoso.local -SiteCode MCM -CollectionName "All Desktop and Server Clients"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteCode,

    [Parameter(Mandatory)]
    [string]$SiteServer,

    [string]$CollectionName,

    [switch]$DetectOnly
)

$ErrorActionPreference = 'Stop'

# ============================================================================
# Desired-state table
# ============================================================================

$KeyPathSchannel = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols'
$KeyPathNet64    = 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319'
$KeyPathNet32    = 'SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'

$Settings = @(
    # === Legacy protocols disabled ===
    @{ SettingName = 'SSL2_0-Server-Enabled';            KeyPath = "$KeyPathSchannel\SSL 2.0\Server"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'SSL2_0-Server-DisabledByDefault';  KeyPath = "$KeyPathSchannel\SSL 2.0\Server"; ValueName = 'DisabledByDefault'; Value = '1' }
    @{ SettingName = 'SSL2_0-Client-Enabled';            KeyPath = "$KeyPathSchannel\SSL 2.0\Client"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'SSL2_0-Client-DisabledByDefault';  KeyPath = "$KeyPathSchannel\SSL 2.0\Client"; ValueName = 'DisabledByDefault'; Value = '1' }

    @{ SettingName = 'SSL3_0-Server-Enabled';            KeyPath = "$KeyPathSchannel\SSL 3.0\Server"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'SSL3_0-Server-DisabledByDefault';  KeyPath = "$KeyPathSchannel\SSL 3.0\Server"; ValueName = 'DisabledByDefault'; Value = '1' }
    @{ SettingName = 'SSL3_0-Client-Enabled';            KeyPath = "$KeyPathSchannel\SSL 3.0\Client"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'SSL3_0-Client-DisabledByDefault';  KeyPath = "$KeyPathSchannel\SSL 3.0\Client"; ValueName = 'DisabledByDefault'; Value = '1' }

    @{ SettingName = 'TLS1_0-Server-Enabled';            KeyPath = "$KeyPathSchannel\TLS 1.0\Server"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'TLS1_0-Server-DisabledByDefault';  KeyPath = "$KeyPathSchannel\TLS 1.0\Server"; ValueName = 'DisabledByDefault'; Value = '1' }
    @{ SettingName = 'TLS1_0-Client-Enabled';            KeyPath = "$KeyPathSchannel\TLS 1.0\Client"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'TLS1_0-Client-DisabledByDefault';  KeyPath = "$KeyPathSchannel\TLS 1.0\Client"; ValueName = 'DisabledByDefault'; Value = '1' }

    @{ SettingName = 'TLS1_1-Server-Enabled';            KeyPath = "$KeyPathSchannel\TLS 1.1\Server"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'TLS1_1-Server-DisabledByDefault';  KeyPath = "$KeyPathSchannel\TLS 1.1\Server"; ValueName = 'DisabledByDefault'; Value = '1' }
    @{ SettingName = 'TLS1_1-Client-Enabled';            KeyPath = "$KeyPathSchannel\TLS 1.1\Client"; ValueName = 'Enabled';           Value = '0' }
    @{ SettingName = 'TLS1_1-Client-DisabledByDefault';  KeyPath = "$KeyPathSchannel\TLS 1.1\Client"; ValueName = 'DisabledByDefault'; Value = '1' }

    # === TLS 1.2 enabled ===
    @{ SettingName = 'TLS1_2-Server-Enabled';            KeyPath = "$KeyPathSchannel\TLS 1.2\Server"; ValueName = 'Enabled';           Value = '1' }
    @{ SettingName = 'TLS1_2-Server-DisabledByDefault';  KeyPath = "$KeyPathSchannel\TLS 1.2\Server"; ValueName = 'DisabledByDefault'; Value = '0' }
    @{ SettingName = 'TLS1_2-Client-Enabled';            KeyPath = "$KeyPathSchannel\TLS 1.2\Client"; ValueName = 'Enabled';           Value = '1' }
    @{ SettingName = 'TLS1_2-Client-DisabledByDefault';  KeyPath = "$KeyPathSchannel\TLS 1.2\Client"; ValueName = 'DisabledByDefault'; Value = '0' }

    # === .NET Framework 4.x strong crypto ===
    @{ SettingName = 'NET64-SchUseStrongCrypto';         KeyPath = $KeyPathNet64;                      ValueName = 'SchUseStrongCrypto';      Value = '1' }
    @{ SettingName = 'NET64-SystemDefaultTlsVersions';   KeyPath = $KeyPathNet64;                      ValueName = 'SystemDefaultTlsVersions'; Value = '1' }
    @{ SettingName = 'NET32-SchUseStrongCrypto';         KeyPath = $KeyPathNet32;                      ValueName = 'SchUseStrongCrypto';      Value = '1' }
    @{ SettingName = 'NET32-SystemDefaultTlsVersions';   KeyPath = $KeyPathNet32;                      ValueName = 'SystemDefaultTlsVersions'; Value = '1' }
)

# ============================================================================
# Connect to MECM
# ============================================================================

$modulePath = Join-Path (Split-Path $ENV:SMS_ADMIN_UI_PATH -Parent) "ConfigurationManager.psd1"
if (-not (Get-Module ConfigurationManager -ErrorAction SilentlyContinue)) {
    if (Test-Path $modulePath) {
        Import-Module $modulePath
    }
    else {
        throw "ConfigurationManager module not found. Run this from a machine with the MECM admin console installed."
    }
}

$OriginalLocation = Get-Location

if (-not (Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $SiteServer | Out-Null
}
Set-Location "${SiteCode}:"

try {
    $CIName = "Compliance: TLS Legacy Disable"
    $CBName = "Compliance TLS Legacy Disable"

    Write-Host "Creating Configuration Item: $CIName"

    $ci = New-CMConfigurationItem `
        -Name $CIName `
        -Description "Disables SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1 in SCHANNEL (server + client). Enables TLS 1.2. Forces .NET Framework 4.x to SystemDefaultTlsVersions and SchUseStrongCrypto in both 64-bit and WOW6432Node paths. 24 native reg-value settings." `
        -CreationType WindowsOS

    Write-Host "  Adding 24 native reg-value settings..."

    foreach ($s in $Settings) {
        $params = @{
            InputObject           = $ci
            Name                  = $s.SettingName
            Description           = "$($s.KeyPath)\$($s.ValueName) = $($s.Value)"
            Hive                  = 'LocalMachine'
            KeyName               = $s.KeyPath
            ValueName             = $s.ValueName
            DataType              = 'Integer'
            Is64Bit               = $true
            ValueRule             = $true
            RuleName              = "$($s.SettingName) equals $($s.Value)"
            ExpressionOperator    = 'IsEquals'
            ExpectedValue         = $s.Value
            NoncomplianceSeverity = 'Critical'
            ReportNoncompliance   = $true
            RemediateDword        = $true
        }
        if (-not $DetectOnly) { $params.Remediate = $true }
        Add-CMComplianceSettingRegistryKeyValue @params
    }

    Write-Host "  CI created with 24 settings." -ForegroundColor Green

    $ci = Get-CMConfigurationItem -Name $CIName -Fast

    Write-Host "Creating Configuration Baseline: $CBName"

    New-CMBaseline `
        -Name $CBName `
        -Description "Enforces SCHANNEL legacy protocol disable + TLS 1.2 enable + .NET strong crypto. CIS / DISA STIG mapped."

    Set-CMBaseline -Name $CBName -AddOSConfigurationItem $ci.CI_ID

    Write-Host "  Baseline created." -ForegroundColor Green

    if ($CollectionName) {
        Write-Host "Deploying baseline to: $CollectionName"

        $schedule = New-CMSchedule -RecurInterval Days -RecurCount 1

        New-CMBaselineDeployment `
            -Name $CBName `
            -CollectionName $CollectionName `
            -EnableEnforcement (-not $DetectOnly) `
            -OverrideServiceWindow $false `
            -GenerateAlert $false `
            -MonitoredByScom $false `
            -Schedule $schedule

        $mode = if ($DetectOnly) { "DETECT ONLY" } else { "DETECT + REMEDIATE" }
        Write-Host "  Deployed daily, mode: $mode" -ForegroundColor Green
    }
    else {
        Write-Host ""
        Write-Host "Baseline created but NOT deployed. Re-run with -CollectionName." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Control:   TLS Legacy Disable (SCHANNEL + .NET 4.x)"
    Write-Host "CI:        $CIName"
    Write-Host "Baseline:  $CBName"
    Write-Host "Mode:      $(if ($DetectOnly) { 'Detect only' } else { 'Detect + remediate' })"
    Write-Host "Settings:  $($Settings.Count) reg DWORDs"
    Write-Host "Reboot:    Required for SCHANNEL to reload protocol config"
}
finally {
    Set-Location $OriginalLocation
}
