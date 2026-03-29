<#
.SYNOPSIS
    Tails a log file inside a Hyper-V VM via PowerShell Direct.

.DESCRIPTION
    Connects to a Hyper-V VM using PowerShell Direct and continuously tails
    a specified log file. Lines containing ERROR are shown in red, WARNING
    in yellow. Polls every N seconds.

.PARAMETER VMName
    Name of the Hyper-V VM to connect to.

.PARAMETER LogPath
    Full path to the log file inside the VM.

.PARAMETER Credential
    PSCredential for the VM. If omitted, you will be prompted.

.PARAMETER IntervalSeconds
    Polling interval in seconds. Default: 5.

.EXAMPLE
    $cred = Get-Credential contoso\LabAdmin
    .\Watch-VMLog.ps1 -VMName CM01 -LogPath C:\ConfigMgrSetup.log -Credential $cred

.EXAMPLE
    .\Watch-VMLog.ps1 -VMName DC01 -LogPath C:\Windows\debug\dcpromo.log
#>
param(
    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter(Mandatory)]
    [string]$LogPath,

    [PSCredential]$Credential,

    [int]$IntervalSeconds = 5
)

if (-not $Credential) {
    $Credential = Get-Credential -Message "Credentials for $VMName"
}

Write-Host "Tailing $LogPath on $VMName (every ${IntervalSeconds}s)..." -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
Write-Host ""

$lastLine = 0
while ($true) {
    try {
        $lines = Invoke-Command -VMName $VMName -Credential $Credential -ScriptBlock {
            param($Path)
            if (Test-Path $Path) { Get-Content $Path }
        } -ArgumentList $LogPath -ErrorAction Stop

        if ($lines -and $lines.Count -gt $lastLine) {
            $newLines = $lines[$lastLine..($lines.Count - 1)]
            foreach ($l in $newLines) {
                if ($l -match 'ERROR') {
                    Write-Host $l -ForegroundColor Red
                } elseif ($l -match 'WARNING') {
                    Write-Host $l -ForegroundColor Yellow
                } else {
                    Write-Host $l
                }
            }
            $lastLine = $lines.Count
        }
    } catch {
        Write-Host "  (waiting for VM...)" -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds $IntervalSeconds
}
