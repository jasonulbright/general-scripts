#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Post-reset automation script. Runs at first logon after factory reset.

.DESCRIPTION
    Executed automatically via unattend.xml FirstLogonCommands after a
    zero-touch factory reset. Applies offline domain join, installs
    critical apps, bootstraps the MECM client, and cleans up the
    temporary admin account.

    Idempotent: checks a registry flag before running. Safe to re-run
    manually if needed.

.PARAMETER ConfigPath
    Path to Reset-Config.json. Default: C:\Recovery\Customizations\Reset-Config.json
#>

param(
    [string]$ConfigPath = 'C:\Recovery\Customizations\Reset-Config.json'
)

$ErrorActionPreference = 'Continue'
$stagingPath = 'C:\Recovery\Customizations'
$logPath = Join-Path $stagingPath 'post-setup.log'

Start-Transcript -Path $logPath -Append

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Zero-Touch Post-Reset Setup" -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Idempotent guard ---
$regPath = 'HKLM:\SOFTWARE\WinReset'
$completedValue = Get-ItemProperty -Path $regPath -Name 'SetupComplete' -ErrorAction SilentlyContinue
if ($completedValue.SetupComplete -eq 1) {
    Write-Host "Post-setup already completed. Exiting." -ForegroundColor Green
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

# --- Import WiFi profiles ---
$wifiDir = Join-Path $stagingPath 'WifiProfiles'
if (Test-Path $wifiDir) {
    $profiles = Get-ChildItem $wifiDir -Filter '*.xml' -ErrorAction SilentlyContinue
    if ($profiles) {
        Write-Host ""
        Write-Host "Importing WiFi profiles..."
        foreach ($p in $profiles) {
            $result = netsh wlan add profile filename="$($p.FullName)" user=all 2>&1
            Write-Host "  WiFi: $($p.BaseName) - $result"
        }
    }
}

# --- Offline domain join ---
$djoinBlob = Join-Path $stagingPath 'odjblob.txt'
if (Test-Path $djoinBlob) {
    Write-Host ""
    Write-Host "Applying offline domain join..."
    $djoinResult = & djoin.exe /requestODJ /loadfile "$djoinBlob" /windowspath "$env:SystemRoot" /localos 2>&1
    Write-Host "  djoin result: $djoinResult"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Domain join blob applied successfully. Will complete on reboot." -ForegroundColor Green
    } else {
        Write-Host "  WARNING: djoin returned exit code $LASTEXITCODE" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: No djoin blob found at $djoinBlob. Device will not be domain-joined." -ForegroundColor Yellow
}

# --- Install apps ---
$installerDir = Join-Path $stagingPath 'Installers'

foreach ($appName in @('Zscaler', 'TeamViewerHost')) {
    $appConfig = $config.Apps.$appName
    if (-not $appConfig) { continue }

    $installerFile = Get-ChildItem $installerDir -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$($appName -replace 'Host','')*" } |
        Select-Object -First 1

    if (-not $installerFile) {
        Write-Host "WARNING: Installer for $appName not found in $installerDir" -ForegroundColor Yellow
        continue
    }

    Write-Host ""
    Write-Host "Installing $appName..."
    Write-Host "  Installer: $($installerFile.FullName)"
    Write-Host "  Args: $($appConfig.SilentArgs)"

    if ($installerFile.Extension -eq '.msi') {
        $proc = Start-Process msiexec.exe -ArgumentList "/i `"$($installerFile.FullName)`" $($appConfig.SilentArgs)" -Wait -PassThru -NoNewWindow
    } else {
        $proc = Start-Process -FilePath $installerFile.FullName -ArgumentList $appConfig.SilentArgs -Wait -PassThru -NoNewWindow
    }

    Write-Host "  Exit code: $($proc.ExitCode)"

    if ($appConfig.ValidationPath -and (Test-Path $appConfig.ValidationPath)) {
        Write-Host "  Validated: $($appConfig.ValidationPath) exists" -ForegroundColor Green
    } elseif ($appConfig.ValidationPath) {
        Write-Host "  WARNING: Validation path not found: $($appConfig.ValidationPath)" -ForegroundColor Yellow
    }
}

# --- Install MECM client ---
if ($config.MECMClient) {
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
        Write-Host "  ccmsetup started. Will complete in background (~10-15 min)." -ForegroundColor Green
    } else {
        Write-Host "WARNING: MECM client installer not found. Manual install required." -ForegroundColor Yellow
    }
}

# --- Disable auto-logon ---
Write-Host ""
Write-Host "Disabling auto-logon..."
$winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Remove-ItemProperty -Path $winlogonPath -Name 'DefaultPassword' -ErrorAction SilentlyContinue
Set-ItemProperty -Path $winlogonPath -Name 'AutoAdminLogon' -Value '0' -ErrorAction SilentlyContinue
Write-Host "  Auto-logon disabled."

# --- Schedule temp admin cleanup ---
$tempUser = $config.TempAdmin.Username
if ($tempUser) {
    Write-Host "Scheduling temp admin cleanup ($tempUser)..."
    $cleanupScript = "Remove-LocalUser -Name '$tempUser' -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName 'WinReset-Cleanup' -Confirm:`$false -ErrorAction SilentlyContinue"
    $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"$cleanupScript`""
    $taskTrigger = New-ScheduledTaskTrigger -AtStartup
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
    Register-ScheduledTask -TaskName 'WinReset-Cleanup' -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Force | Out-Null
    Write-Host "  Cleanup task registered (runs at next boot)."
}

# --- Set completion flag ---
New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path $regPath -Name 'SetupComplete' -Value 1
Set-ItemProperty -Path $regPath -Name 'CompletedAt' -Value (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Set-ItemProperty -Path $regPath -Name 'ComputerName' -Value $env:COMPUTERNAME

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Post-setup complete. Rebooting..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Stop-Transcript

# Reboot to complete domain join
Restart-Computer -Force
