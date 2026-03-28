#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Prepares a device for zero-touch factory reset with automatic domain rejoin.

.DESCRIPTION
    Captures machine identity, generates an offline domain join blob, stages
    recovery payload (unattend.xml, post-setup script, app installers), then
    triggers a factory reset. After reset, the device automatically:
    - Skips OOBE
    - Rejoins the domain with the same hostname
    - Installs Zscaler, TeamViewer Host, MECM client
    - Cleans up and reboots to the login screen

    All staging is done in C:\Recovery\ which survives the factory reset.

.PARAMETER ConfigPath
    Path to Reset-Config.json. Default: same directory as this script.

.PARAMETER Force
    Skip confirmation prompt. Required for SCCM-deployed execution.

.PARAMETER SkipReset
    Stage everything but do not trigger the factory reset. For testing.

.EXAMPLE
    # Test staging without resetting
    .\Invoke-PrepareReset.ps1 -SkipReset

.EXAMPLE
    # Full zero-touch reset (SCCM deployment)
    .\Invoke-PrepareReset.ps1 -Force

.EXAMPLE
    # Interactive with confirmation
    .\Invoke-PrepareReset.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'Reset-Config.json'),
    [switch]$Force,
    [switch]$SkipReset
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message, [string]$Level = 'INFO')
    $color = switch ($Level) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'White' }
    }
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$ts] [$Level] $Message" -ForegroundColor $color
}

# ── Load config ──────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Zero-Touch Factory Reset - Prep" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $ConfigPath)) {
    Write-Step "Config not found: $ConfigPath" -Level FAIL
    exit 1
}
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
Write-Step "Config loaded: $ConfigPath"

$customizationsPath = $config.Recovery.CustomizationsPath
$autoApplyPath      = $config.Recovery.AutoApplyPath

# ── Validate prerequisites ───────────────────────────────────────────────────

Write-Step "Validating prerequisites..."

# OS version
$build = [System.Environment]::OSVersion.Version.Build
if ($build -lt 19044) {
    Write-Step "Windows 10 21H2+ or Windows 11 required (build $build)" -Level FAIL
    exit 1
}
Write-Step "  OS build: $build" -Level OK

# MDM_RemoteWipe
$mdmWipe = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_RemoteWipe' -ErrorAction SilentlyContinue
if (-not $mdmWipe) {
    Write-Step "  MDM_RemoteWipe CIM class not found" -Level FAIL
    exit 1
}
Write-Step "  MDM_RemoteWipe: available" -Level OK

# djoin.exe
$djoinPath = Join-Path $env:SystemRoot 'System32\djoin.exe'
if (-not (Test-Path $djoinPath)) {
    Write-Step "  djoin.exe not found" -Level FAIL
    exit 1
}
Write-Step "  djoin.exe: found" -Level OK

# ── Capture machine state ────────────────────────────────────────────────────

$computerName = $env:COMPUTERNAME
Write-Step "Computer name: $computerName"

# Get current OU via ADSI
try {
    $searcher = [adsisearcher]"(&(objectCategory=computer)(cn=$computerName))"
    $result = $searcher.FindOne()
    if ($result) {
        $dn = $result.Properties['distinguishedname'][0]
        # Extract OU portion (remove the CN=computername, part)
        $ouDN = ($dn -split ',', 2)[1]
        Write-Step "Current OU: $ouDN"
    } else {
        $ouDN = $config.Domain.DefaultOU
        Write-Step "Could not find computer in AD. Using default OU: $ouDN" -Level WARN
    }
} catch {
    $ouDN = $config.Domain.DefaultOU
    Write-Step "AD query failed. Using default OU: $ouDN" -Level WARN
}

$domainFQDN = $config.Domain.FQDN

# ── Generate offline domain join blob ────────────────────────────────────────

Write-Step "Generating offline domain join blob..."

$djoinBlobPath = Join-Path $env:TEMP "odjblob_$computerName.txt"

# Load djoin service account credentials if available
$djoinKeyFile  = Join-Path $PSScriptRoot 'djoin.key'
$djoinUserFile = Join-Path $PSScriptRoot 'djoin.user'
$djoinPassFile = Join-Path $PSScriptRoot 'djoin.pass'

$djoinArgs = @(
    '/provision',
    '/domain', $domainFQDN,
    '/machine', $computerName,
    '/machineou', $ouDN,
    '/savefile', $djoinBlobPath,
    '/reuse'
)

if ((Test-Path $djoinKeyFile) -and (Test-Path $djoinUserFile) -and (Test-Path $djoinPassFile)) {
    # Run djoin with service account credentials
    $aesKey     = [System.IO.File]::ReadAllBytes($djoinKeyFile)
    $djoinUser  = (Get-Content $djoinUserFile -Raw).Trim()
    $securePass = ConvertTo-SecureString (Get-Content $djoinPassFile -Raw).Trim() -Key $aesKey
    $djoinCred  = New-Object PSCredential($djoinUser, $securePass)

    Write-Step "  Using service account: $djoinUser"
    $proc = Start-Process -FilePath $djoinPath -ArgumentList $djoinArgs -Credential $djoinCred -Wait -PassThru -NoNewWindow
} else {
    # Run as current user (must have domain join permissions)
    Write-Step "  No djoin credentials found. Running as current user." -Level WARN
    $proc = Start-Process -FilePath $djoinPath -ArgumentList $djoinArgs -Wait -PassThru -NoNewWindow
}

if ($proc.ExitCode -ne 0) {
    Write-Step "  djoin.exe failed with exit code $($proc.ExitCode)" -Level FAIL
    exit 1
}

if (-not (Test-Path $djoinBlobPath)) {
    Write-Step "  djoin blob not created at $djoinBlobPath" -Level FAIL
    exit 1
}
Write-Step "  Blob generated: $djoinBlobPath" -Level OK

# ── Stage recovery payload ───────────────────────────────────────────────────

Write-Step "Staging recovery payload..."

# Create directories
foreach ($dir in @($customizationsPath, $autoApplyPath, "$customizationsPath\Installers")) {
    New-Item -Path $dir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

# Copy djoin blob
Copy-Item $djoinBlobPath -Destination "$customizationsPath\odjblob.txt" -Force
Write-Step "  Staged: odjblob.txt" -Level OK

# Copy app installers from InstallSequence
if ($config.InstallSequence) {
    foreach ($app in $config.InstallSequence) {
        if (-not $app.InstallerFile) { continue }

        # Look for the installer in common locations
        $found = $false
        foreach ($searchPath in @("$PSScriptRoot\Installers", "$PSScriptRoot", "$env:TEMP")) {
            $candidate = Join-Path $searchPath $app.InstallerFile
            if (Test-Path $candidate) {
                Copy-Item $candidate -Destination "$customizationsPath\Installers\$($app.InstallerFile)" -Force
                Write-Step "  Staged: $($app.Name) -> $($app.InstallerFile)" -Level OK
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Step "  Not found: $($app.Name) ($($app.InstallerFile)) -- place in .\Installers\ before running" -Level WARN
        }
    }
}

# Copy MECM client (optional)
if ($config.MECMClient -and $config.MECMClient.InstallerPath) {
    $ccmDir = "$customizationsPath\CCMSetup"
    New-Item -Path $ccmDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    if (Test-Path $config.MECMClient.InstallerPath -ErrorAction SilentlyContinue) {
        Copy-Item $config.MECMClient.InstallerPath -Destination "$ccmDir\ccmsetup.exe" -Force
        Write-Step "  Staged: MECM client" -Level OK
    } else {
        Write-Step "  MECM client not reachable: $($config.MECMClient.InstallerPath)" -Level WARN
    }
}

# Export WiFi profiles
if ($config.WiFi.ExportProfiles) {
    $wifiDir = "$customizationsPath\WifiProfiles"
    New-Item -Path $wifiDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $null = netsh wlan export profile folder="$wifiDir" key=clear 2>&1
    $profileCount = (Get-ChildItem $wifiDir -Filter '*.xml' -ErrorAction SilentlyContinue).Count
    Write-Step "  WiFi profiles exported: $profileCount" -Level OK
}

# Copy post-setup.ps1
Copy-Item (Join-Path $PSScriptRoot 'post-setup.ps1') -Destination "$customizationsPath\post-setup.ps1" -Force
Write-Step "  Staged: post-setup.ps1" -Level OK

# Copy config (with runtime values)
$config | ConvertTo-Json -Depth 5 | Set-Content -Path "$customizationsPath\Reset-Config.json" -Encoding UTF8 -Force
Write-Step "  Staged: Reset-Config.json" -Level OK

# ── Generate unattend.xml ────────────────────────────────────────────────────

Write-Step "Generating unattend.xml..."

$templatePath = Join-Path $PSScriptRoot 'unattend-template.xml'
if (-not (Test-Path $templatePath)) {
    Write-Step "  Template not found: $templatePath" -Level FAIL
    exit 1
}

$unattend = Get-Content $templatePath -Raw
$unattend = $unattend -replace '{{COMPUTERNAME}}', $computerName
$locale   = if ($config.Locale)   { $config.Locale }   else { 'en-US' }
$keyboard = if ($config.Keyboard) { $config.Keyboard } else { '0409:00000409' }
$unattend = $unattend -replace '{{LOCALE}}', $locale
$unattend = $unattend -replace '{{KEYBOARD}}', $keyboard

Set-Content -Path "$autoApplyPath\unattend.xml" -Value $unattend -Encoding UTF8 -Force
Write-Step "  Generated: $autoApplyPath\unattend.xml" -Level OK
Write-Step "  Computer name: $computerName"
Write-Step "  Post-setup runs as SYSTEM via SetupComplete.cmd (no temp admin)"

# ── Validate staging ─────────────────────────────────────────────────────────

Write-Step "Validating staged artifacts..."

$required = @(
    "$autoApplyPath\unattend.xml",
    "$customizationsPath\post-setup.ps1",
    "$customizationsPath\Reset-Config.json",
    "$customizationsPath\odjblob.txt"
)

$missing = @()
foreach ($path in $required) {
    if (Test-Path $path) {
        Write-Step "  Found: $(Split-Path $path -Leaf)" -Level OK
    } else {
        Write-Step "  MISSING: $path" -Level FAIL
        $missing += $path
    }
}

if ($missing.Count -gt 0) {
    Write-Step "Staging incomplete. $($missing.Count) required file(s) missing. Aborting." -Level FAIL
    exit 1
}

Write-Step "All artifacts staged successfully." -Level OK

# ── Trigger reset ────────────────────────────────────────────────────────────

if ($SkipReset) {
    Write-Host ""
    Write-Step "SkipReset specified. Staging complete. Device NOT reset." -Level WARN
    Write-Host ""
    Write-Host "  Recovery payload staged at:" -ForegroundColor DarkGray
    Write-Host "    $customizationsPath" -ForegroundColor DarkGray
    Write-Host "    $autoApplyPath" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  To proceed with reset, run:" -ForegroundColor DarkGray
    Write-Host "    .\Invoke-FactoryReset.ps1 -Force" -ForegroundColor White
    Write-Host ""
    exit 0
}

if (-not $Force) {
    Write-Host ""
    Write-Host "  !! FACTORY RESET !!" -ForegroundColor Red
    Write-Host "  Device: $computerName" -ForegroundColor Red
    Write-Host "  Domain: $domainFQDN" -ForegroundColor Red
    Write-Host "  OU: $ouDN" -ForegroundColor Red
    Write-Host ""
    Write-Host "  ALL user data will be removed." -ForegroundColor Red
    Write-Host "  The device will automatically rejoin the domain" -ForegroundColor Red
    Write-Host "  and reinstall apps after reset." -ForegroundColor Red
    Write-Host ""
    $confirm = Read-Host "  Type YES to proceed"
    if ($confirm -ne 'YES') {
        Write-Step "Aborted by user." -Level WARN
        exit 0
    }
}

if ($PSCmdlet.ShouldProcess($computerName, 'Zero-Touch Factory Reset')) {
    Write-Step "Triggering factory reset..."
    & (Join-Path $PSScriptRoot 'Invoke-FactoryReset.ps1') -Force
}
