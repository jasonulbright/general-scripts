#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Factory resets a Windows device using the MDM Bridge WMI provider.

.DESCRIPTION
    Replaces 'systemreset -factoryreset' which was removed in Windows 24H2.
    Uses the MDM_RemoteWipe CIM class (root\cimv2\mdm\dmmap) to trigger a
    full wipe. Works on domain-joined, workgroup, and MDM-enrolled devices
    without requiring Intune enrollment.

    The device will reboot and enter OOBE (Out-of-Box Experience) after the
    wipe completes. All user data, profiles, and installed applications are
    removed. The OS is preserved (no reimage).

    Original concept: reddit.com/r/SCCM/comments/1rv47wj (u/ops)

.PARAMETER ComputerName
    Remote computer(s) to reset. Requires PSRemoting access and local admin
    on the target. If omitted, resets the local machine.

.PARAMETER Force
    Skips the confirmation prompt. Required for unattended/scripted use.

.PARAMETER WhatIf
    Shows what would happen without executing the reset.

.EXAMPLE
    # Reset the local machine (prompts for confirmation)
    .\Invoke-FactoryReset.ps1

.EXAMPLE
    # Reset a remote machine without prompting
    .\Invoke-FactoryReset.ps1 -ComputerName PC001 -Force

.EXAMPLE
    # Reset multiple machines (SCCM deployed script)
    .\Invoke-FactoryReset.ps1 -Force

.NOTES
    - Windows 10 21H2+ / Windows 11 required (MDM Bridge WMI provider)
    - Removes ALL user data, profiles, and applications
    - The OS installation is preserved (not a reimage)
    - Device enters OOBE after reboot
    - For SCCM deployment: use -Force flag, run as SYSTEM
    - For Autopilot re-enrollment: device will re-register if hardware hash
      is in the Autopilot service
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$ComputerName,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Invoke-DeviceWipe {
    param([string]$Target = 'localhost')

    $namespaceName = 'root\cimv2\mdm\dmmap'
    $className     = 'MDM_RemoteWipe'
    $methodName    = 'doWipeMethod'

    try {
        $sessionParams = @{}
        if ($Target -ne 'localhost' -and $Target -ne $env:COMPUTERNAME) {
            $sessionParams.ComputerName = $Target
        }

        $session = New-CimSession @sessionParams

        $instance = Get-CimInstance -Namespace $namespaceName -ClassName $className -CimSession $session -ErrorAction Stop
        if (-not $instance) {
            throw "MDM_RemoteWipe class not found. Ensure the device is running Windows 10 21H2+ or Windows 11."
        }

        $params = New-Object Microsoft.Management.Infrastructure.CimMethodParametersCollection
        $param = [Microsoft.Management.Infrastructure.CimMethodParameter]::Create('param', '', 'String', 'In')
        $params.Add($param)

        $session.InvokeMethod($namespaceName, $instance, $methodName, $params)

        Write-Host "Factory reset initiated on $Target. Device will reboot into OOBE." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to initiate factory reset on ${Target}: $($_.Exception.Message)"
    }
    finally {
        if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }
    }
}

# --- Main ---

$targets = if ($ComputerName) { $ComputerName } else { @('localhost') }

foreach ($target in $targets) {
    $displayName = if ($target -eq 'localhost') { $env:COMPUTERNAME } else { $target }

    # Pre-flight: check for recovery payload (zero-touch automation)
    if ($target -eq 'localhost' -or $target -eq $env:COMPUTERNAME) {
        $hasPayload = (Test-Path 'C:\Recovery\Customizations\post-setup.ps1') -and
                      (Test-Path 'C:\Recovery\AutoApply\unattend.xml')
        if (-not $hasPayload) {
            Write-Host ''
            Write-Host '  NOTE: No recovery payload found in C:\Recovery\.' -ForegroundColor Yellow
            Write-Host '  The device will reset to a blank OOBE with no automation.' -ForegroundColor Yellow
            Write-Host '  Run Invoke-PrepareReset.ps1 first for zero-touch reset.' -ForegroundColor Yellow
            Write-Host ''
            if (-not $Force) {
                $proceed = Read-Host '  Continue with bare reset? (YES/NO)'
                if ($proceed -ne 'YES') { Write-Host '  Aborted.'; continue }
            }
        }
    }

    if (-not $Force) {
        Write-Host ''
        Write-Host "  WARNING: This will factory reset $displayName" -ForegroundColor Red
        Write-Host '  All user data, profiles, and applications will be removed.' -ForegroundColor Red
        Write-Host '  The device will reboot into OOBE (Out-of-Box Experience).' -ForegroundColor Red
        Write-Host ''
        $confirm = Read-Host "  Type YES to confirm factory reset of $displayName"
        if ($confirm -ne 'YES') {
            Write-Host '  Aborted.' -ForegroundColor Yellow
            continue
        }
    }

    if ($PSCmdlet.ShouldProcess($displayName, 'Factory Reset (MDM_RemoteWipe)')) {
        Invoke-DeviceWipe -Target $target
    }
}
