#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Forces MECM/SCCM clients to use a specific Management Point by cleaning all
    cached MP references in WMI, registry, and CCM data stores, then restarting
    the CCMExec service.

.PARAMETER NewMP
    Hostname of the target Management Point. Default: sccm01.contoso.com

.PARAMETER BadMPs
    Array of old MP hostnames to scrub. Default: oldmp01.contoso.com, oldmp02.contoso.com

.PARAMETER SiteCode
    3-letter MECM site code (e.g. MCM). Leave blank to skip authority rewrite.

.PARAMETER ServiceRestartWaitSec
    Seconds to wait after stopping CCMExec before restarting. Default: 15

.PARAMETER SkipPolicyTrigger
    Skip the post-restart policy/discovery trigger calls.

.EXAMPLE
    .\Set-MECMManagementPoint.ps1 -NewMP sccm01.contoso.com -SiteCode MCM

.EXAMPLE
    Batch deploy via PS-Remote (100 at a time):

    $computers = Get-Content C:\Temp\clients.txt
    $cred      = Get-Credential
    $sb = [scriptblock]::Create(
        (Get-Content .\Set-MECMManagementPoint.ps1 -Raw) + "`nSet-MECMManagementPoint"
    )
    $batch = 100
    for ($i = 0; $i -lt $computers.Count; $i += $batch) {
        $chunk = $computers[$i..([Math]::Min($i+$batch-1,$computers.Count-1))]
        Invoke-Command -ComputerName $chunk -Credential $cred -ScriptBlock $sb -AsJob -JobName "MP_Fix_$i"
    }
    Get-Job -Name "MP_Fix_*" | Wait-Job | Receive-Job |
        Select-Object ComputerName, Success, COM_CurrentMP |
        Export-Csv C:\Temp\MP_Fix_Results.csv -NoTypeInformation
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [string]   $NewMP                 = 'sccm01.contoso.com',
    [string[]] $BadMPs                = @('oldmp01.contoso.com', 'oldmp02.contoso.com'),
    [string]   $SiteCode              = '',
    [int]      $ServiceRestartWaitSec = 15,
    [switch]   $SkipPolicyTrigger
)

#region Helpers

function Write-Log {
    param([string]$Msg, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level] $Msg"
    switch ($Level) {
        'WARN'  { Write-Warning $line }
        'ERROR' { Write-Error   $line }
        default { Write-Verbose $line -Verbose }
    }
}

function Stop-CCMService {
    Write-Log "Stopping CcmExec service..."
    try {
        Stop-Service -Name CcmExec -Force -ErrorAction Stop
        $waited = 0
        while ((Get-Service CcmExec -ErrorAction SilentlyContinue).Status -ne 'Stopped' -and $waited -lt 60) {
            Start-Sleep -Seconds 2
            $waited += 2
        }
        Write-Log "CcmExec stopped."
    }
    catch {
        Write-Log "Could not stop CcmExec: $_" 'WARN'
    }
}

function Start-CCMService {
    Write-Log "Waiting $ServiceRestartWaitSec s before starting CcmExec..."
    Start-Sleep -Seconds $ServiceRestartWaitSec
    try {
        Start-Service -Name CcmExec -ErrorAction Stop
        Write-Log "CcmExec started."
    }
    catch {
        Write-Log "Could not start CcmExec: $_" 'ERROR'
    }
}

#endregion

#region Registry Cleanup

function Clear-RegistryMP {
    Write-Log "--- Registry cleanup ---"

    function Set-RegValue {
        param($Path, $Name, $Value, $Type = 'String')
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
        Write-Log "  REG SET: $Path\$Name = $Value"
    }

    function Remove-RegValue {
        param($Path, $Name)
        if (Test-Path $Path) {
            try {
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
                Write-Log "  REG DEL: $Path\$Name"
            }
            catch { }
        }
    }

    $lsPath = 'HKLM:\SOFTWARE\Microsoft\CCM\LocationServices'
    Set-RegValue $lsPath 'LastUsedMP'              $NewMP
    Set-RegValue $lsPath 'HttpManagementPointList' $NewMP
    Set-RegValue $lsPath 'ManagementPoint'         $NewMP

    $ccmPath = 'HKLM:\SOFTWARE\Microsoft\CCM'
    Set-RegValue $ccmPath 'CCMHTTPPORT'  '80'   'DWORD'
    Set-RegValue $ccmPath 'CCMHTTPSPORT' '443'  'DWORD'
    Set-RegValue $ccmPath 'CCMFIRSTMP'   $NewMP
    Set-RegValue $ccmPath 'CCMSERVER'    $NewMP

    foreach ($badMP in $BadMPs) {
        Remove-RegValue $ccmPath $badMP
    }

    $smsMCPath = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client'
    Set-RegValue $smsMCPath 'GPRequestedManagementPoints' $NewMP
    Set-RegValue $smsMCPath 'AssignedManagementPoint'     $NewMP

    $setupPath = 'HKLM:\SOFTWARE\Microsoft\CCMSetup'
    if (Test-Path $setupPath) {
        Set-RegValue $setupPath 'LastSuccessfulInstallParams' "/mp:$NewMP SMSSITECODE=AUTO"
    }

    if ($SiteCode) {
        $authPath = 'HKLM:\SOFTWARE\Microsoft\SMS\Mobile Client\Software Distribution'
        Set-RegValue $authPath 'Authority' "SMS:$SiteCode"
    }

    Write-Log "Registry cleanup complete."
}

#endregion

#region WMI Cleanup

function Clear-WMIMP {
    Write-Log "--- WMI cleanup ---"

    try {
        $lsMPs = Get-CimInstance -Namespace root\ccm\LocationServices `
                                 -ClassName SMS_ManagementPointListFromCache `
                                 -ErrorAction SilentlyContinue
        foreach ($entry in $lsMPs) {
            $mpHost = $entry.MPName -replace 'https?://', '' -replace '/.*', ''
            if ($mpHost -ne $NewMP) {
                Write-Log "  WMI REMOVE (MP cache): $($entry.MPName)"
                Remove-CimInstance -InputObject $entry -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log "  SMS_ManagementPointListFromCache query skipped: $_" 'WARN'
    }

    try {
        $authInstances = Get-CimInstance -Namespace root\ccm `
                                         -ClassName CCM_Authority `
                                         -ErrorAction SilentlyContinue
        foreach ($auth in $authInstances) {
            $mpHost = $auth.CurrentManagementPoint -replace 'https?://', '' -replace '/.*', '' -replace ':.*', ''
            if ($mpHost -and $mpHost -ne $NewMP) {
                Write-Log "  WMI: CCM_Authority shows $($auth.CurrentManagementPoint) - attempting COM override"
                try {
                    $client = New-Object -ComObject Microsoft.SMS.Client -ErrorAction Stop
                    $client.SetCurrentManagementPoint($NewMP, 1)
                    Write-Log "  COM: SetCurrentManagementPoint -> $NewMP"
                }
                catch {
                    Write-Log "  COM unavailable (service stopped) - reg fix will apply on restart." 'WARN'
                }
            }
        }
    }
    catch {
        Write-Log "  CCM_Authority query skipped: $_" 'WARN'
    }

    try {
        $badPattern = $BadMPs -join '|'
        $policyMPs  = Get-CimInstance -Namespace 'root\ccm\Policy\Machine\RequestedConfig' `
                                      -ClassName CCM_SoftwareDistribution `
                                      -ErrorAction SilentlyContinue |
                      Where-Object { $_.ADV_MandatoryAssignments -match $badPattern }
        foreach ($pol in $policyMPs) {
            Write-Log "  WMI REMOVE stale policy: $($pol.__PATH)"
            Remove-CimInstance -InputObject $pol -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Log "  Policy namespace query skipped (non-critical): $_" 'WARN'
    }

    try {
        $smsAuth    = Get-CimInstance -Namespace root\cimv2\sms `
                                      -ClassName SMS_Authority `
                                      -ErrorAction SilentlyContinue
        $badPattern = $BadMPs -join '|'
        foreach ($sa in $smsAuth) {
            if ($sa.Name -and $sa.Name -match $badPattern) {
                Write-Log "  WMI REMOVE SMS_Authority: $($sa.Name)"
                Remove-CimInstance -InputObject $sa -ErrorAction SilentlyContinue
            }
        }
    }
    catch { }

    Write-Log "WMI cleanup complete."
}

#endregion

#region File Cache Cleanup

function Clear-CCMFileCache {
    Write-Log "--- File cache cleanup ---"

    $ccmDir = "$env:SystemRoot\CCM"

    $safeToDelete = @(
        "$ccmDir\MP_List.xml",
        "$ccmDir\ccmstore.sdf"
    )

    foreach ($file in $safeToDelete) {
        if (Test-Path $file) {
            try {
                Remove-Item $file -Force -ErrorAction Stop
                Write-Log "  DELETED: $file"
            }
            catch {
                Write-Log "  Could not delete $file : $_" 'WARN'
            }
        }
    }

    if (Test-Path $ccmDir) {
        $badPattern = $BadMPs -join '|'
        Get-ChildItem -Path $ccmDir -Filter '*.xml' -Recurse -ErrorAction SilentlyContinue |
        ForEach-Object {
            $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and $content -match $badPattern) {
                Write-Log "  DELETED (bad MP ref): $($_.FullName)"
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Log "File cache cleanup complete."
}

#endregion

#region Policy Triggers

function Invoke-PolicyTriggers {
    Write-Log "--- Triggering policy/discovery ---"

    $waited = 0
    while ((Get-Service CcmExec -ErrorAction SilentlyContinue).Status -ne 'Running' -and $waited -lt 90) {
        Start-Sleep -Seconds 3
        $waited += 3
    }

    if ((Get-Service CcmExec -ErrorAction SilentlyContinue).Status -ne 'Running') {
        Write-Log "CcmExec did not come back up in time - skipping triggers." 'WARN'
        return
    }

    $triggers = @{
        'Machine Policy Retrieval'  = '{00000000-0000-0000-0000-000000000021}'
        'Machine Policy Evaluation' = '{00000000-0000-0000-0000-000000000022}'
        'Discovery Data Collection' = '{00000000-0000-0000-0000-000000000003}'
        'MP List Refresh'           = '{00000000-0000-0000-0000-000000000061}'
    }

    foreach ($name in $triggers.Keys) {
        try {
            Invoke-CimMethod -Namespace root\ccm `
                             -ClassName SMS_Client `
                             -MethodName TriggerSchedule `
                             -Arguments @{ sScheduleID = $triggers[$name] } `
                             -ErrorAction Stop | Out-Null
            Write-Log "  Triggered: $name"
        }
        catch {
            Write-Log "  Could not trigger '$name': $_" 'WARN'
        }
    }

    try {
        $client = New-Object -ComObject Microsoft.SMS.Client -ErrorAction Stop
        $client.TriggerSchedule('{00000000-0000-0000-0000-000000000021}') | Out-Null
        Write-Log "  COM trigger: Machine Policy Retrieval sent."
    }
    catch { }

    Write-Log "Policy triggers complete."
}

#endregion

#region Verification

function Get-CurrentMP {
    Write-Log "--- Verification ---"
    $results = [ordered]@{}

    $results['Reg_LastUsedMP'] = (Get-ItemProperty `
        'HKLM:\SOFTWARE\Microsoft\CCM\LocationServices' `
        -Name LastUsedMP -ErrorAction SilentlyContinue).LastUsedMP

    try {
        $auth = Get-CimInstance -Namespace root\ccm -ClassName CCM_Authority -ErrorAction SilentlyContinue |
                Select-Object -First 1
        $results['WMI_CurrentMP'] = $auth.CurrentManagementPoint
    }
    catch {
        $results['WMI_CurrentMP'] = 'query failed'
    }

    try {
        $client = New-Object -ComObject Microsoft.SMS.Client -ErrorAction Stop
        $results['COM_CurrentMP'] = $client.GetCurrentManagementPoint()
    }
    catch {
        $results['COM_CurrentMP'] = 'COM unavailable'
    }

    $escapedMP = [regex]::Escape($NewMP)
    foreach ($k in $results.Keys) {
        $val  = $results[$k]
        $icon = if ($val -match $escapedMP) { '[OK]' } else { '[!!]' }
        Write-Log "  $icon $k = $val"
    }

    return $results
}

#endregion

#region Main

function Set-MECMManagementPoint {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Log "======================================================"
    Write-Log " MECM MP Remediation starting on $env:COMPUTERNAME"
    Write-Log " Target MP  : $NewMP"
    Write-Log " Evicting   : $($BadMPs -join ', ')"
    Write-Log " Site Code  : $(if ($SiteCode) { $SiteCode } else { '(not set)' })"
    Write-Log "======================================================"

    if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Remediate MECM Management Point")) {

        Stop-CCMService
        Clear-RegistryMP
        Clear-WMIMP
        Clear-CCMFileCache
        Start-CCMService

        if (-not $SkipPolicyTrigger) {
            Invoke-PolicyTriggers
        }

        $verif     = Get-CurrentMP
        $escapedMP = [regex]::Escape($NewMP)

        Write-Log "======================================================"
        Write-Log " Remediation complete on $env:COMPUTERNAME"
        Write-Log "======================================================"

        [PSCustomObject]@{
            ComputerName   = $env:COMPUTERNAME
            Timestamp      = Get-Date
            TargetMP       = $NewMP
            Reg_LastUsedMP = $verif['Reg_LastUsedMP']
            WMI_CurrentMP  = $verif['WMI_CurrentMP']
            COM_CurrentMP  = $verif['COM_CurrentMP']
            Success        = ($verif.Values | Where-Object { $_ -match $escapedMP }).Count -gt 0
        }
    }
}

#endregion

# Auto-execute when run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Set-MECMManagementPoint
}