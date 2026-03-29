<#
.SYNOPSIS
    Discovers log files and running processes inside a Hyper-V VM.

.DESCRIPTION
    Connects to a Hyper-V VM via PowerShell Direct and enumerates:
    - Running processes matching a name filter
    - Log files in common locations (C:\, Windows\Temp, user temp, SMS logs)
    - Log files in custom search paths

    Useful for identifying which log to tail when debugging a remote install.

.PARAMETER VMName
    Name of the Hyper-V VM to connect to.

.PARAMETER Credential
    PSCredential for the VM. If omitted, you will be prompted.

.PARAMETER ProcessFilter
    Wildcard filter for process names. Default: "setup*","configmgr*".

.PARAMETER AdditionalLogPaths
    Extra directories to search for .log files inside the VM.

.EXAMPLE
    $cred = Get-Credential contoso\LabAdmin
    .\Get-VMLogInventory.ps1 -VMName CM01 -Credential $cred

.EXAMPLE
    .\Get-VMLogInventory.ps1 -VMName CM01 -Credential $cred -ProcessFilter "sql*","sms*"
#>
param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [PSCredential]$Credential,

    [string[]]$ProcessFilter = @("setup*", "configmgr*"),

    [string[]]$AdditionalLogPaths = @()
)

if (-not $Credential) {
    $Credential = Get-Credential -Message "Credentials for $VMName"
}

Invoke-Command -VMName $VMName -Credential $Credential -ArgumentList @(,$ProcessFilter), @(,$AdditionalLogPaths) -ScriptBlock {
    param([string[]]$ProcFilter, [string[]]$ExtraPaths)

    Write-Host "=== Running processes ===" -ForegroundColor Cyan
    $procs = Get-Process -Name $ProcFilter -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Format-Table Name, Id, @{N='CPU(s)';E={[math]::Round($_.CPU,1)}}, StartTime -AutoSize
    } else {
        Write-Host "  No matching processes"
    }

    Write-Host "=== Log files in C:\ ===" -ForegroundColor Cyan
    Get-ChildItem C:\*.log -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Format-Table Name, @{N='Size(KB)';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize

    Write-Host "=== SMS/ConfigMgr logs ===" -ForegroundColor Cyan
    $smsLogs = 'C:\Program Files\Microsoft Configuration Manager\Logs'
    if (Test-Path $smsLogs) {
        Get-ChildItem $smsLogs -Filter *.log -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 10 |
            Format-Table Name, @{N='Size(KB)';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize
    } else {
        Write-Host "  Not found: $smsLogs"
    }

    Write-Host "=== Temp logs ===" -ForegroundColor Cyan
    $searchPaths = @("$env:TEMP", "$env:SystemRoot\Temp") + $ExtraPaths
    foreach ($dir in $searchPaths) {
        if (-not (Test-Path $dir)) { continue }
        $logs = Get-ChildItem $dir -Filter *.log -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 5
        if ($logs) {
            Write-Host "  $dir" -ForegroundColor Gray
            $logs | Format-Table Name, @{N='Size(KB)';E={[math]::Round($_.Length/1KB,1)}}, LastWriteTime -AutoSize
        }
    }
}
