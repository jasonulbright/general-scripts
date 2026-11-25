#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -RunAsAdministrator

# Run on a lab client, never on a production machine or the dev PC. The tests create local
# users named zzpc-* with real profiles, run the runner script in child processes (to read
# the exit code), and remove everything they created. Every run uses -IncludeAccounts
# 'zzpc-*', so no real profile is selected.

BeforeAll {
    $script:Folder = Split-Path -Path $PSCommandPath -Parent
    $script:Runner = Join-Path -Path $script:Folder -ChildPath 'Invoke-UserProfileCleanup.ps1'
    $script:ProfileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $script:Users = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $script:Native64 = Join-Path -Path $env:windir -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script:Native32 = Join-Path -Path $env:windir -ChildPath 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'

    if (-not ('UpcRun.Native' -as [type])) {
        Add-Type -Namespace UpcRun -Name Native -MemberDefinition @'
[DllImport("userenv.dll", CharSet=CharSet.Unicode)]
public static extern int CreateProfile([MarshalAs(UnmanagedType.LPWStr)] string pszUserSid, [MarshalAs(UnmanagedType.LPWStr)] string pszUserName, System.Text.StringBuilder pszProfilePath, uint cchProfilePath);
'@
    }

    function New-StaleTestProfile {
        param ([string]$Name, [double]$DaysOld = 100)
        $objPassword = ConvertTo-SecureString -String ([guid]::NewGuid().ToString('N') + 'Aa1!') -AsPlainText -Force
        [void](New-LocalUser -Name $Name -Password $objPassword -AccountNeverExpires)
        $script:Users.Add($Name)
        $strSid = (Get-LocalUser -Name $Name).SID.Value
        $objPath = New-Object -TypeName System.Text.StringBuilder -ArgumentList 260
        $intResult = [UpcRun.Native]::CreateProfile($strSid, $Name, $objPath, 260)
        if ($intResult -ne 0) {
            throw ('CreateProfile failed: 0x{0:X8}' -f $intResult)
        }
        $longFileTime = [datetime]::UtcNow.AddDays(-$DaysOld).ToFileTimeUtc()
        $strKey = $script:ProfileListPath + '\' + $strSid
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeLow' -Type DWord `
            -Value ([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -band 0xFFFFFFFFL)), 0))
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeHigh' -Type DWord `
            -Value ([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -shr 32)), 0))
        return [pscustomobject]@{ Name = $Name; Sid = $strSid; Path = $objPath.ToString() }
    }

    function Invoke-Child {
        param ([string]$Executable, [string[]]$Argument)
        $arrOutput = @(& $Executable @Argument 2>&1 | ForEach-Object { "$_" })
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($arrOutput -join "`n") }
    }

    function Remove-StaleTestProfile {
        param ([string]$Name)
        $objUser = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
        if ($objUser) {
            $objCim = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID = '{0}'" -f $objUser.SID.Value)
            if ($objCim -and (-not $objCim.Loaded)) {
                Remove-CimInstance -InputObject $objCim
            }
            $strKey = $script:ProfileListPath + '\' + $objUser.SID.Value
            if (Test-Path -LiteralPath $strKey) {
                Remove-Item -LiteralPath $strKey -Recurse -Force
            }
            Remove-LocalUser -Name $Name
        }
        $strFolder = Join-Path -Path ([Environment]::ExpandEnvironmentVariables('%SystemDrive%\Users')) -ChildPath $Name
        if (Test-Path -LiteralPath $strFolder) {
            . (Join-Path -Path $script:Folder -ChildPath 'UserProfileCleanup.Engine.ps1')
            Remove-UserProfileFolderTree -Path $strFolder
        }
    }
}

AfterAll {
    foreach ($strUser in @($script:Users)) {
        try {
            Remove-StaleTestProfile -Name $strUser
        } catch {
            Write-Warning ("Cleanup of user '{0}' failed: {1}" -f $strUser, $_.Exception.Message)
        }
    }
}

Describe 'Invoke-UserProfileCleanup.ps1' {
    BeforeEach {
        $script:Log = Join-Path -Path $TestDrive -ChildPath ('run-{0}.log' -f [guid]::NewGuid().ToString('N'))
    }

    It 'lists the items and removes nothing with -DetectOnly' {
        $objProfile = New-StaleTestProfile -Name 'zzpc-run1'
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-IncludeAccounts', 'zzpc-run1', '-DetectOnly', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 0
        $objResult.Output | Should -BeLike '*StaleProfile*zzpc-run1*'
        Test-Path -LiteralPath $objProfile.Path | Should -BeTrue
        [System.IO.File]::ReadAllText($script:Log) | Should -BeLike '*Would remove*'
    }

    It 'removes the profile, logs it and exits 0' {
        $strPath = Join-Path -Path $env:SystemDrive -ChildPath 'Users\zzpc-run1'
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-IncludeAccounts', 'zzpc-run1', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 0
        $objResult.Output | Should -BeLike '*Found 1, removed 1, failed 0*'
        Test-Path -LiteralPath $strPath | Should -BeFalse
        $strLog = [System.IO.File]::ReadAllText($script:Log)
        $strLog | Should -BeLike '*Profile removed*'
        $strLog | Should -BeLike '*Done: found 1, removed 1, failed 0*'
    }

    It 'does nothing and exits 0 when no item qualifies' {
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-IncludeAccounts', 'zzpc-nomatch-*', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 0
        $objResult.Output | Should -BeLike '*Found 0, removed 0, failed 0*'
    }

    It 'starts the 64-bit PowerShell when it is started as 32-bit, and returns its exit code' {
        if (-not (Test-Path -LiteralPath $script:Native32)) {
            Set-ItResult -Skipped -Because 'No 32-bit PowerShell on this OS.'
            return
        }
        $objResult = Invoke-Child -Executable $script:Native32 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-IncludeAccounts', 'zzpc-nomatch-*', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($script:Log) | Should -BeLike '*64-bit process True*'
    }

    It 'exits 1 when an item cannot be removed' {
        $objProfile = New-StaleTestProfile -Name 'zzpc-run2'
        $strLocked = Join-Path -Path $objProfile.Path -ChildPath 'AppData\locked.txt'
        [System.IO.File]::WriteAllText($strLocked, 'x')
        $objHandle = [System.IO.File]::Open($strLocked, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        try {
            $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
                '-Days', '90', '-IncludeAccounts', 'zzpc-run2', '-Scope', 'StaleProfile', '-LogPath', $script:Log)
        } finally {
            $objHandle.Dispose()
        }
        $objResult.ExitCode | Should -Be 1
        $objResult.Output | Should -BeLike '*FAILED*'
        [System.IO.File]::ReadAllText($script:Log) | Should -BeLike '*ERROR*'
    }

    It 'exits 2 when the engine file is missing' {
        $strLone = Join-Path -Path $TestDrive -ChildPath 'lone'
        [void][System.IO.Directory]::CreateDirectory($strLone)
        Copy-Item -LiteralPath $script:Runner -Destination $strLone
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path -Path $strLone -ChildPath 'Invoke-UserProfileCleanup.ps1'), '-Days', '90', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 2
        $objResult.Output | Should -BeLike '*Engine file not found*'
    }

    It 'exits 2 for an invalid wildcard pattern and removes nothing' {
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-ExcludeAccounts', 'svc_[', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 2
        Test-Path -LiteralPath $script:Log | Should -BeFalse
    }

    It 'rejects a day count outside 1 to 3650' {
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner, '-Days', '0', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Not -Be 0
    }

    It 'works with the command line form for a task sequence step' {
        $strCommand = "& { `$ErrorActionPreference='Stop'; Set-Location -LiteralPath '" + $script:Folder + "'; try { .\Invoke-UserProfileCleanup.ps1 -Days 90 -IncludeAccounts @('zzpc-nomatch-*') -LogPath '" + $script:Log + "' } catch { exit 2 }; if (`$null -eq `$LASTEXITCODE) { exit 2 }; exit `$LASTEXITCODE }"
        $objResult = Invoke-Child -Executable $script:Native32 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $strCommand)
        $objResult.ExitCode | Should -Be 0
        $objResult.Output | Should -BeLike '*Found 0*'
    }

    It 'returns 2, not 0, in that command line form when the runner cannot start' {
        $strCommand = "& { `$ErrorActionPreference='Stop'; Set-Location -LiteralPath '" + $script:Folder + "'; try { .\Invoke-UserProfileCleanup.ps1 -Days 0 } catch { exit 2 }; if (`$null -eq `$LASTEXITCODE) { exit 2 }; exit `$LASTEXITCODE }"
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $strCommand)
        $objResult.ExitCode | Should -Be 2
    }

    It 'passes a log path with an apostrophe and a non-ASCII character through the 32-bit relaunch' {
        if (-not (Test-Path -LiteralPath $script:Native32)) {
            Set-ItResult -Skipped -Because 'No 32-bit PowerShell on this OS.'
            return
        }
        $strOddLog = Join-Path -Path $TestDrive -ChildPath ("o'brien_" + [char]0x00FC + '.log')
        $objResult = Invoke-Child -Executable $script:Native32 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-IncludeAccounts', 'zzpc-nomatch-*', '-DetectOnly', '-LogPath', $strOddLog)
        $objResult.ExitCode | Should -Be 0
        Test-Path -LiteralPath $strOddLog | Should -BeTrue
    }

    It 'keeps -DetectOnly through the 32-bit relaunch' {
        if (-not (Test-Path -LiteralPath $script:Native32)) {
            Set-ItResult -Skipped -Because 'No 32-bit PowerShell on this OS.'
            return
        }
        $null = Invoke-Child -Executable $script:Native32 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Runner,
            '-Days', '90', '-IncludeAccounts', 'zzpc-nomatch-*', '-DetectOnly', '-LogPath', $script:Log)
        [System.IO.File]::ReadAllText($script:Log) | Should -BeLike '*detect only True*'
    }

    It 'exits 2 when the engine file does not load' {
        $strBroken = Join-Path -Path $TestDrive -ChildPath 'broken'
        [void][System.IO.Directory]::CreateDirectory($strBroken)
        Copy-Item -LiteralPath $script:Runner -Destination $strBroken
        [System.IO.File]::WriteAllText((Join-Path -Path $strBroken -ChildPath 'UserProfileCleanup.Engine.ps1'), "function Broken {`n")
        $objResult = Invoke-Child -Executable $script:Native64 -Argument @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            (Join-Path -Path $strBroken -ChildPath 'Invoke-UserProfileCleanup.ps1'), '-Days', '90', '-LogPath', $script:Log)
        $objResult.ExitCode | Should -Be 2
    }
}
