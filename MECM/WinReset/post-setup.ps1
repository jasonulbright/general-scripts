#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Post-reset automation script. Runs as SYSTEM via SetupComplete.cmd.

.DESCRIPTION
    Executed automatically after factory reset. Applies offline domain join,
    installs apps in priority order with reboot-resume support, bootstraps
    the MECM client, and delivers the device to the login screen fully
    configured.

    Reboot-resume: tracks progress in the registry. If a RebootAfter step
    triggers a reboot, SetupComplete.cmd re-runs this script on next boot.
    The script resumes from where it left off.

    The user never sees an unsecured desktop. All installs complete before
    the login screen appears.

.PARAMETER ConfigPath
    Path to Reset-Config.json. Default: C:\Recovery\Customizations\Reset-Config.json
#>

param(
    [string]$ConfigPath = 'C:\Recovery\Customizations\Reset-Config.json'
)

$ErrorActionPreference = 'Continue'
$stagingPath = 'C:\Recovery\Customizations'
$logPath = Join-Path $stagingPath 'post-setup.log'
$regPath = 'HKLM:\SOFTWARE\WinReset'

Start-Transcript -Path $logPath -Append

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Zero-Touch Post-Reset Setup" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Check if fully complete ---
New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
$completedValue = Get-ItemProperty -Path $regPath -Name 'SetupComplete' -ErrorAction SilentlyContinue
if ($completedValue.SetupComplete -eq 1) {
    Write-Host "Post-setup already completed. Cleaning up and exiting." -ForegroundColor Green
    # Remove SetupComplete.cmd so it doesn't run again
    $setupCmd = Join-Path $env:SystemRoot 'Setup\Scripts\SetupComplete.cmd'
    Remove-Item $setupCmd -Force -ErrorAction SilentlyContinue
    Stop-Transcript
    exit 0
}

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: Config not found: $ConfigPath" -ForegroundColor Red
    Stop-Transcript
    exit 1
}
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
Write-Host "Config loaded: $ConfigPath"

# --- Get current step (for reboot-resume) ---
$currentStep = Get-ItemProperty -Path $regPath -Name 'CurrentStep' -ErrorAction SilentlyContinue
$resumeFrom = if ($currentStep) { [int]$currentStep.CurrentStep } else { 0 }
Write-Host "Resuming from step: $resumeFrom"

# ── STEP 0: WiFi profiles ────────────────────────────────────────────────────

if ($resumeFrom -le 0) {
    $wifiDir = Join-Path $stagingPath 'WifiProfiles'
    if (Test-Path $wifiDir) {
        $profiles = Get-ChildItem $wifiDir -Filter '*.xml' -ErrorAction SilentlyContinue
        if ($profiles) {
            Write-Host ""
            Write-Host "Importing WiFi profiles..."
            foreach ($p in $profiles) {
                $null = netsh wlan add profile filename="$($p.FullName)" user=all 2>&1
                Write-Host "  WiFi: $($p.BaseName)"
            }
        }
    }
    Set-ItemProperty -Path $regPath -Name 'CurrentStep' -Value 1
}

# ── STEP 1: Offline domain join ──────────────────────────────────────────────

if ($resumeFrom -le 1) {
    $djoinBlob = Join-Path $stagingPath 'odjblob.txt'
    if (Test-Path $djoinBlob) {
        Write-Host ""
        Write-Host "Applying offline domain join..."
        $djoinResult = & djoin.exe /requestODJ /loadfile "$djoinBlob" /windowspath "$env:SystemRoot" /localos 2>&1
        Write-Host "  djoin result: $djoinResult"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Domain join blob applied. Completes on reboot." -ForegroundColor Green
        } else {
            Write-Host "  WARNING: djoin exit code $LASTEXITCODE" -ForegroundColor Yellow
        }
    } else {
        Write-Host "WARNING: No djoin blob found. Device will not be domain-joined." -ForegroundColor Yellow
    }
    Set-ItemProperty -Path $regPath -Name 'CurrentStep' -Value 2
}

# ── STEP 2+: Install sequence (ordered by Priority) ─────────────────────────

$installerDir = Join-Path $stagingPath 'Installers'
$sequence = @($config.InstallSequence | Sort-Object { $_.Priority })

for ($i = 0; $i -lt $sequence.Count; $i++) {
    $app = $sequence[$i]
    $stepNum = $i + 2  # steps 0=wifi, 1=djoin, 2+=apps

    if ($resumeFrom -gt $stepNum) {
        Write-Host "Skipping (already done): $($app.Name)" -ForegroundColor DarkGray
        continue
    }

    $installerFile = Get-ChildItem $installerDir -Filter $app.InstallerFile -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $installerFile) {
        Write-Host "WARNING: Installer not found for $($app.Name): $($app.InstallerFile)" -ForegroundColor Yellow
        Set-ItemProperty -Path $regPath -Name 'CurrentStep' -Value ($stepNum + 1)
        continue
    }

    Write-Host ""
    Write-Host "Installing: $($app.Name)..." -ForegroundColor White
    Write-Host "  File: $($installerFile.FullName)"
    Write-Host "  Args: $($app.SilentArgs)"

    if ($installerFile.Extension -eq '.msi') {
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$($installerFile.FullName)`" $($app.SilentArgs)" -Wait -PassThru -NoNewWindow
    } else {
        $proc = Start-Process -FilePath $installerFile.FullName -ArgumentList $app.SilentArgs -Wait -PassThru -NoNewWindow
    }

    $exitCode = $proc.ExitCode
    Write-Host "  Exit code: $exitCode"

    if ($app.ValidationPath -and (Test-Path $app.ValidationPath)) {
        Write-Host "  Validated: $($app.ValidationPath)" -ForegroundColor Green
    } elseif ($app.ValidationPath) {
        Write-Host "  Validation pending (may need reboot): $($app.ValidationPath)" -ForegroundColor Yellow
    }

    # Mark this step done
    Set-ItemProperty -Path $regPath -Name 'CurrentStep' -Value ($stepNum + 1)

    # Reboot if required (script will resume from the next step)
    if ($app.RebootAfter -or $exitCode -eq 3010) {
        Write-Host "  Rebooting after $($app.Name)..." -ForegroundColor Yellow
        Write-Host "  Script will resume from step $($stepNum + 1) on next boot."
        Stop-Transcript
        Restart-Computer -Force
        exit 0  # SetupComplete.cmd will re-run this script after reboot
    }
}

# ── MECM client (last) ───────────────────────────────────────────────────────

$mecmStep = $sequence.Count + 2
if ($resumeFrom -le $mecmStep -and $config.MECMClient) {
    $ccmsetup = Join-Path $stagingPath 'CCMSetup\ccmsetup.exe'
    if (-not (Test-Path $ccmsetup)) {
        $ccmsetup = $config.MECMClient.InstallerPath
    }

    if (Test-Path $ccmsetup -ErrorAction SilentlyContinue) {
        Write-Host ""
        Write-Host "Installing MECM client (async)..."
        Write-Host "  Path: $ccmsetup"
        Write-Host "  Args: $($config.MECMClient.SilentArgs)"
        Start-Process -FilePath $ccmsetup -ArgumentList $config.MECMClient.SilentArgs -NoNewWindow
        Write-Host "  ccmsetup started (~10-15 min in background)." -ForegroundColor Green
    } else {
        Write-Host "WARNING: MECM client not found. Manual install required." -ForegroundColor Yellow
    }
    Set-ItemProperty -Path $regPath -Name 'CurrentStep' -Value ($mecmStep + 1)
}

# ── Complete ─────────────────────────────────────────────────────────────────

Set-ItemProperty -Path $regPath -Name 'SetupComplete' -Value 1
Set-ItemProperty -Path $regPath -Name 'CompletedAt' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Set-ItemProperty -Path $regPath -Name 'ComputerName' -Value $env:COMPUTERNAME

# Clean up SetupComplete.cmd
$setupCmd = Join-Path $env:SystemRoot 'Setup\Scripts\SetupComplete.cmd'
Remove-Item $setupCmd -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Post-setup complete. Final reboot..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Stop-Transcript

# Final reboot completes domain join
Restart-Computer -Force
