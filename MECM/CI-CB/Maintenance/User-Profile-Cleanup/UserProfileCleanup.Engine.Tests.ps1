#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -RunAsAdministrator

# Run on a lab client, never on a production machine or the dev PC. The tests create local
# users named zzpc-* with real profiles, and remove them again. Every query uses
# -IncludeAccount 'zzpc-*' (or a test SID), so no real profile is selected or deleted.

BeforeAll {
    $strScriptFolder = Split-Path -Path $PSCommandPath -Parent
    . (Join-Path -Path $strScriptFolder -ChildPath 'UserProfileCleanup.Engine.ps1')

    $script:ProfileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    $script:ProfileGuidPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileGuid'
    $script:ProfilesDirectory = [Environment]::ExpandEnvironmentVariables(
        [string](Get-ItemPropertyValue -LiteralPath $script:ProfileListPath -Name 'ProfilesDirectory'))
    $script:CreatedUser = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $script:CreatedFolder = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $script:CreatedKey = New-Object -TypeName 'System.Collections.Generic.List[string]'
    $script:GuidParentCreated = $false

    if (-not ('UpcTest.Native' -as [type])) {
        Add-Type -Namespace UpcTest -Name Native -MemberDefinition @'
[DllImport("userenv.dll", CharSet=CharSet.Unicode)]
public static extern int CreateProfile([MarshalAs(UnmanagedType.LPWStr)] string pszUserSid, [MarshalAs(UnmanagedType.LPWStr)] string pszUserName, System.Text.StringBuilder pszProfilePath, uint cchProfilePath);
'@
    }

    function New-TestProfile {
        param ([string]$Name)
        $objPassword = ConvertTo-SecureString -String ([guid]::NewGuid().ToString('N') + 'Aa1!') -AsPlainText -Force
        [void](New-LocalUser -Name $Name -Password $objPassword -AccountNeverExpires)
        $script:CreatedUser.Add($Name)
        $strSid = (Get-LocalUser -Name $Name).SID.Value
        $objPath = New-Object -TypeName System.Text.StringBuilder -ArgumentList 260
        $intResult = [UpcTest.Native]::CreateProfile($strSid, $Name, $objPath, 260)
        if ($intResult -ne 0) {
            throw ('CreateProfile failed: 0x{0:X8}' -f $intResult)
        }
        $script:CreatedFolder.Add($objPath.ToString())
        return [pscustomobject]@{ Name = $Name; Sid = $strSid; Path = $objPath.ToString() }
    }

    function Set-TestProfileStamp {
        param ([string]$Sid, [double]$DaysOld)
        $strKey = $script:ProfileListPath + '\' + $Sid
        $longFileTime = [datetime]::UtcNow.AddDays(-$DaysOld).ToFileTimeUtc()
        $intLow = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -band 0xFFFFFFFFL)), 0)
        $intHigh = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -shr 32)), 0)
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeLow' -Value $intLow -Type DWord
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeHigh' -Value $intHigh -Type DWord
    }

    function Set-TestFileAge {
        param ([string]$Path, [double]$DaysOld)
        $objTime = [datetime]::UtcNow.AddDays(-$DaysOld)
        if (Test-Path -LiteralPath $Path -PathType Container) {
            [System.IO.Directory]::SetLastWriteTimeUtc($Path, $objTime)
        } else {
            [System.IO.File]::SetLastWriteTimeUtc($Path, $objTime)
        }
    }

    function Get-TestItem {
        param ([string]$Pattern = 'zzpc-*', [int]$MaxAgeDays = 90, [string[]]$Kind)
        $hashtableArgument = @{ MaxAgeDays = $MaxAgeDays; IncludeAccount = @($Pattern) }
        if ($Kind) {
            $hashtableArgument['Kind'] = $Kind
        }
        return @(Get-UserProfileCleanupItem @hashtableArgument)
    }

    function Remove-TestProfile {
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
    }
}

AfterAll {
    foreach ($strUser in @($script:CreatedUser)) {
        try {
            Remove-TestProfile -Name $strUser
        } catch {
            Write-Warning ("Cleanup of user '{0}' failed: {1}" -f $strUser, $_.Exception.Message)
        }
    }
    foreach ($strKey in @($script:CreatedKey)) {
        if (Test-Path -LiteralPath $strKey) {
            Remove-Item -LiteralPath $strKey -Recurse -Force
        }
    }
    if ($script:GuidParentCreated -and (Test-Path -LiteralPath $script:ProfileGuidPath)) {
        Remove-Item -LiteralPath $script:ProfileGuidPath -Recurse -Force
    }
    foreach ($strFolder in @($script:CreatedFolder)) {
        if (Test-Path -LiteralPath $strFolder) {
            Remove-UserProfileFolderTree -Path $strFolder
        }
    }
}

Describe 'ConvertFrom-UserProfileFileTime' {
    It 'joins the DWORD halves' {
        $longFileTime = ([datetime]'2026-01-02T03:04:05Z').ToFileTimeUtc()
        $intLow = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -band 0xFFFFFFFFL)), 0)
        $intHigh = [int]($longFileTime -shr 32)
        $objResult = ConvertFrom-UserProfileFileTime -LowPart $intLow -HighPart $intHigh
        $objResult | Should -Be ([datetime]'2026-01-02T03:04:05Z').ToUniversalTime()
    }

    It 'returns null for a missing or zero value' {
        ConvertFrom-UserProfileFileTime -LowPart $null -HighPart 5 | Should -BeNullOrEmpty
        ConvertFrom-UserProfileFileTime -LowPart 0 -HighPart 0 | Should -BeNullOrEmpty
    }
}

Describe 'Test-UserProfileAccountMatch' {
    It 'matches any candidate against any pattern' {
        Test-UserProfileAccountMatch -Pattern @('svc_*') -Candidate @('S-1-5-21-1', 'svc_backup') | Should -BeTrue
        Test-UserProfileAccountMatch -Pattern @('CONTOSO\kiosk*') -Candidate @('CONTOSO\kiosk01') | Should -BeTrue
    }

    It 'does not match when nothing fits, and an empty list never matches' {
        Test-UserProfileAccountMatch -Pattern @('svc_*') -Candidate @('jdoe') | Should -BeFalse
        Test-UserProfileAccountMatch -Pattern @() -Candidate @('jdoe') | Should -BeFalse
    }
}

Describe 'Get-UserProfileCleanupItem: stale profiles' {
    BeforeAll {
        $script:Old = New-TestProfile -Name 'zzpc-old'
        $script:Young = New-TestProfile -Name 'zzpc-young'
        $script:Skip = New-TestProfile -Name 'zzpc-skip'
        Set-TestProfileStamp -Sid $script:Old.Sid -DaysOld 100.5
        Set-TestProfileStamp -Sid $script:Young.Sid -DaysOld 5
        Set-TestProfileStamp -Sid $script:Skip.Sid -DaysOld 200
    }

    It 'selects a profile that is older than the limit and keeps a young one' {
        $arrItem = Get-TestItem -Kind 'StaleProfile'
        $arrItem.Sid | Should -Contain $script:Old.Sid
        $arrItem.Sid | Should -Not -Contain $script:Young.Sid
        $objOld = $arrItem | Where-Object { $_.Sid -eq $script:Old.Sid }
        $objOld.Kind | Should -Be 'StaleProfile'
        $objOld.AgeDays | Should -Be 100
        $objOld.Basis | Should -Be 'Registry'
        $objOld.Path | Should -Be $script:Old.Path
    }

    It 'counts whole days: a limit above the age excludes the profile' {
        (Get-TestItem -MaxAgeDays 101 -Kind 'StaleProfile').Sid | Should -Not -Contain $script:Old.Sid
        (Get-TestItem -MaxAgeDays 100 -Kind 'StaleProfile').Sid | Should -Contain $script:Old.Sid
    }

    It 'keeps an account that matches ExcludeAccount' {
        $arrItem = @(Get-UserProfileCleanupItem -MaxAgeDays 90 -IncludeAccount @('zzpc-*') -ExcludeAccount @('zzpc-sk*') -Kind 'StaleProfile')
        $arrItem.Sid | Should -Contain $script:Old.Sid
        $arrItem.Sid | Should -Not -Contain $script:Skip.Sid
    }

    It 'resolves account names when a pattern has a backslash' {
        $arrItem = @(Get-UserProfileCleanupItem -MaxAgeDays 90 -IncludeAccount @('*\zzpc-old') -Kind 'StaleProfile')
        $arrItem.Sid | Should -Contain $script:Old.Sid
        ($arrItem | Where-Object { $_.Sid -eq $script:Old.Sid }).Account | Should -BeLike '*\zzpc-old'
    }

    It 'never selects a loaded profile' {
        Set-TestProfileStamp -Sid $script:Skip.Sid -DaysOld 200
        $strHive = Join-Path -Path $script:Skip.Path -ChildPath 'NTUSER.DAT'
        $null = & reg.exe load ('HKU\' + $script:Skip.Sid) $strHive
        try {
            (Get-TestItem -Kind 'StaleProfile').Sid | Should -Not -Contain $script:Skip.Sid
            $arrResult = @([pscustomobject]@{ Kind = 'StaleProfile'; Sid = $script:Skip.Sid; Account = 'zzpc-skip'; Path = $script:Skip.Path } |
                    Remove-UserProfileCleanupItem -Confirm:$false)
            $arrResult[0].Succeeded | Should -BeFalse
            $arrResult[0].Message | Should -BeLike '*loaded*'
            Test-Path -LiteralPath $script:Skip.Path | Should -BeTrue
        } finally {
            [gc]::Collect()
            $null = & reg.exe unload ('HKU\' + $script:Skip.Sid)
        }
    }

    It 'ignores a SID that is not a user SID, and the built-in Administrator' {
        $arrFakeKey = @(
            @{ Name = 'S-1-5-21-1-2-3-500'; Path = 'C:\Users\zzpc-rid500-missing' },
            @{ Name = 'S-1-5-80-1-2-3-4004'; Path = 'C:\Users\zzpc-service-missing' })
        foreach ($hashtableKey in $arrFakeKey) {
            $strKey = $script:ProfileListPath + '\' + $hashtableKey.Name
            [void](New-Item -Path $strKey -Force)
            $script:CreatedKey.Add($strKey)
            Set-ItemProperty -LiteralPath $strKey -Name 'ProfileImagePath' -Value $hashtableKey.Path
        }
        (Get-TestItem).Path | Should -Not -Contain 'C:\Users\zzpc-rid500-missing'
        (Get-TestItem).Path | Should -Not -Contain 'C:\Users\zzpc-service-missing'
    }

    AfterAll {
        foreach ($strName in @('zzpc-old', 'zzpc-young', 'zzpc-skip')) {
            Remove-TestProfile -Name $strName
        }
    }
}

Describe 'Get-UserProfileCleanupItem: age without registry stamps' {
    BeforeAll {
        $script:Plain = New-TestProfile -Name 'zzpc-plain'
    }

    It 'keeps a profile with a fresh NTUSER.DAT' {
        (Get-TestItem -Kind 'StaleProfile').Sid | Should -Not -Contain $script:Plain.Sid
    }

    It 'uses the NTUSER.DAT write time when no stamp exists' {
        Set-TestFileAge -Path (Join-Path -Path $script:Plain.Path -ChildPath 'NTUSER.DAT') -DaysOld 120
        $objItem = Get-TestItem -Kind 'StaleProfile' | Where-Object { $_.Sid -eq $script:Plain.Sid }
        $objItem.Basis | Should -Be 'NTUSER.DAT'
        $objItem.AgeDays | Should -BeGreaterOrEqual 119
    }

    It 'keeps a profile when no timestamp exists at all' {
        Remove-Item -LiteralPath (Join-Path -Path $script:Plain.Path -ChildPath 'NTUSER.DAT') -Force
        (Get-TestItem -Kind 'StaleProfile').Sid | Should -Not -Contain $script:Plain.Sid
    }

    AfterAll {
        Remove-TestProfile -Name 'zzpc-plain'
    }
}

Describe 'Remove-UserProfileCleanupItem' {
    It 'removes folder, hive and registration of a stale profile' {
        $objProfile = New-TestProfile -Name 'zzpc-rm1'
        Set-TestProfileStamp -Sid $objProfile.Sid -DaysOld 150
        $arrResult = @(Get-TestItem -Kind 'StaleProfile' | Where-Object { $_.Sid -eq $objProfile.Sid } |
                Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult.Count | Should -Be 1
        $arrResult[0].Succeeded | Should -BeTrue
        Test-Path -LiteralPath $objProfile.Path | Should -BeFalse
        Test-Path -LiteralPath ($script:ProfileListPath + '\' + $objProfile.Sid) | Should -BeFalse
        Remove-LocalUser -Name 'zzpc-rm1'
    }

    It 'does nothing with -WhatIf' {
        $objProfile = New-TestProfile -Name 'zzpc-rm2'
        Set-TestProfileStamp -Sid $objProfile.Sid -DaysOld 150
        Get-TestItem -Kind 'StaleProfile' | Where-Object { $_.Sid -eq $objProfile.Sid } | Remove-UserProfileCleanupItem -WhatIf
        Test-Path -LiteralPath $objProfile.Path | Should -BeTrue
        Remove-TestProfile -Name 'zzpc-rm2'
    }

    It 'reports a failure and does not throw' {
        $objItem = [pscustomobject]@{ Kind = 'StaleProfile'; Sid = 'S-1-5-21-1-2-3-4999'; Account = 'zzpc-none'; Path = 'C:\Users\zzpc-none' }
        { $objItem | Remove-UserProfileCleanupItem -Confirm:$false } | Should -Not -Throw
        $arrResult = @($objItem | Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeFalse
    }

    It 'writes one log line for each item' {
        $strLog = Join-Path -Path $TestDrive -ChildPath 'cleanup.log'
        $objItem = [pscustomobject]@{ Kind = 'StaleProfile'; Sid = 'S-1-5-21-1-2-3-4999'; Account = 'zzpc-none'; Path = 'C:\Users\zzpc-none' }
        $null = $objItem | Remove-UserProfileCleanupItem -LogPath $strLog -Confirm:$false
        $arrLine = @(Get-Content -LiteralPath $strLog)
        $arrLine.Count | Should -Be 1
        $arrLine[0] | Should -BeLike '*ERROR*StaleProfile*zzpc-none*'
    }
}

Describe 'Orphan registrations' {
    It 'finds and removes a ProfileList key whose folder is gone' {
        $objProfile = New-TestProfile -Name 'zzpc-orphreg'
        Remove-UserProfileFolderTree -Path $objProfile.Path
        $arrItem = @(Get-TestItem -Kind 'OrphanRegistration' | Where-Object { $_.Sid -eq $objProfile.Sid })
        $arrItem.Count | Should -Be 1
        $arrResult = @($arrItem | Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeTrue
        Test-Path -LiteralPath ($script:ProfileListPath + '\' + $objProfile.Sid) | Should -BeFalse
        Remove-LocalUser -Name 'zzpc-orphreg'
    }

    It 'finds and removes a .bak key whose folder is gone' {
        $strKey = $script:ProfileListPath + '\S-1-5-21-1-2-3-4002.bak'
        [void](New-Item -Path $strKey -Force)
        $script:CreatedKey.Add($strKey)
        Set-ItemProperty -LiteralPath $strKey -Name 'ProfileImagePath' -Value 'C:\Users\zzpc-bak-missing'
        $arrItem = @(Get-TestItem -Kind 'OrphanRegistration' | Where-Object { $_.Sid -eq 'S-1-5-21-1-2-3-4002.bak' })
        $arrItem.Count | Should -Be 1
        $null = $arrItem | Remove-UserProfileCleanupItem -Confirm:$false
        Test-Path -LiteralPath $strKey | Should -BeFalse
    }

    It 'keeps a key when the parent folder is missing (offline volume)' {
        $strKey = $script:ProfileListPath + '\S-1-5-21-1-2-3-4005'
        [void](New-Item -Path $strKey -Force)
        $script:CreatedKey.Add($strKey)
        Set-ItemProperty -LiteralPath $strKey -Name 'ProfileImagePath' -Value 'Q:\NoSuchVolume\zzpc-offline'
        @(Get-TestItem -Pattern 'zzpc-offline').Count | Should -Be 0
    }
}

Describe 'Orphan ProfileGuid keys' {
    It 'finds and removes a key whose SID has no ProfileList key' {
        if (-not (Test-Path -LiteralPath $script:ProfileGuidPath)) {
            [void](New-Item -Path $script:ProfileGuidPath -Force)
            $script:GuidParentCreated = $true
        }
        $strKey = $script:ProfileGuidPath + '\{00000000-aaaa-bbbb-cccc-zzpc00000001}'
        [void](New-Item -Path $strKey -Force)
        $script:CreatedKey.Add($strKey)
        Set-ItemProperty -LiteralPath $strKey -Name 'SidString' -Value 'S-1-5-21-1-2-3-4003'
        $arrItem = @(Get-TestItem -Pattern 'S-1-5-21-1-2-3-4003' -Kind 'OrphanProfileGuid')
        $arrItem.Count | Should -Be 1
        $null = $arrItem | Remove-UserProfileCleanupItem -Confirm:$false
        Test-Path -LiteralPath $strKey | Should -BeFalse
    }
}

Describe 'Safety rules' {
    BeforeAll {
        function New-FakeKey {
            param ([string]$KeyName, [string]$ImagePath, [double]$DaysOld = 0)
            $strKey = $script:ProfileListPath + '\' + $KeyName
            [void](New-Item -Path $strKey -Force)
            $script:CreatedKey.Add($strKey)
            Set-ItemProperty -LiteralPath $strKey -Name 'ProfileImagePath' -Value $ImagePath
            if ($DaysOld -gt 0) {
                Set-TestProfileStamp -Sid $KeyName -DaysOld $DaysOld
            }
        }
    }

    It 'keeps a stale profile when a second key points to the same folder' {
        $objProfile = New-TestProfile -Name 'zzpc-share'
        Set-TestProfileStamp -Sid $objProfile.Sid -DaysOld 200
        (Get-TestItem -Kind 'StaleProfile').Sid | Should -Contain $objProfile.Sid
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-4010' -ImagePath $objProfile.Path
        (Get-TestItem -Kind 'StaleProfile').Sid | Should -Not -Contain $objProfile.Sid
        $arrResult = @([pscustomobject]@{ Kind = 'StaleProfile'; Sid = $objProfile.Sid; Account = 'zzpc-share'; Path = $objProfile.Path } |
                Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeFalse
        $arrResult[0].Message | Should -BeLike '*same folder*'
        Test-Path -LiteralPath $objProfile.Path | Should -BeTrue
        Remove-Item -LiteralPath ($script:ProfileListPath + '\S-1-5-21-1-2-3-4010') -Recurse -Force
        Remove-TestProfile -Name 'zzpc-share'
    }

    It 'keeps a stale profile whose folder is not directly under the profiles directory' {
        $strElsewhere = Join-Path -Path $TestDrive -ChildPath 'zzpc-elsewhere'
        [void][System.IO.Directory]::CreateDirectory($strElsewhere)
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-4011' -ImagePath $strElsewhere -DaysOld 300
        @(Get-TestItem -Pattern 'S-1-5-21-1-2-3-4011' -Kind 'StaleProfile').Count | Should -Be 0
        $arrResult = @([pscustomobject]@{ Kind = 'StaleProfile'; Sid = 'S-1-5-21-1-2-3-4011'; Account = 'x'; Path = $strElsewhere } |
                Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeFalse
        Test-Path -LiteralPath $strElsewhere | Should -BeTrue
    }

    It 'keeps a key that points at the profiles directory itself' {
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-4012' -ImagePath $script:ProfilesDirectory -DaysOld 300
        @(Get-TestItem -Pattern 'S-1-5-21-1-2-3-4012' -Kind 'StaleProfile').Count | Should -Be 0
    }

    It 'keeps a key that points at Public' {
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-4013' -ImagePath (Join-Path -Path $script:ProfilesDirectory -ChildPath 'Public') -DaysOld 300
        @(Get-TestItem -Pattern 'S-1-5-21-1-2-3-4013' -Kind 'StaleProfile').Count | Should -Be 0
    }

    It 'ignores well-known RIDs below 1000' {
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-504' -ImagePath 'C:\Users\zzpc-wdag-missing'
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-501' -ImagePath 'C:\Users\zzpc-guest-missing'
        $arrPath = @((Get-TestItem -Kind 'OrphanRegistration').Path)
        $arrPath | Should -Not -Contain 'C:\Users\zzpc-wdag-missing'
        $arrPath | Should -Not -Contain 'C:\Users\zzpc-guest-missing'
    }

    It 'refuses an item with a SID that is not a user SID' {
        $arrResult = @([pscustomobject]@{ Kind = 'OrphanRegistration'; Sid = 'S-1-5-18'; Account = 'x'; Path = 'C:\Windows\system32\config\systemprofile' } |
                Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeFalse
        Test-Path -LiteralPath ($script:ProfileListPath + '\S-1-5-18') | Should -BeTrue
    }

    It 'refuses an orphan-folder item outside the profiles directory' {
        $strFolder = Join-Path -Path $TestDrive -ChildPath 'zzpc-not-a-profile'
        [void][System.IO.Directory]::CreateDirectory($strFolder)
        $arrResult = @([pscustomobject]@{ Kind = 'OrphanFolder'; Sid = $null; Account = 'x'; Path = $strFolder } |
                Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeFalse
        Test-Path -LiteralPath $strFolder | Should -BeTrue
    }

    It 'treats a registration that uses an 8.3 path as registered' {
        $strFolder = Join-Path -Path $script:ProfilesDirectory -ChildPath 'zzpc-long-folder-name-for-8dot3'
        [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $strFolder -ChildPath 'AppData'))
        $script:CreatedFolder.Add($strFolder)
        [System.IO.File]::WriteAllText((Join-Path -Path $strFolder -ChildPath 'NTUSER.DAT'), 'x')
        Set-TestFileAge -Path (Join-Path -Path $strFolder -ChildPath 'NTUSER.DAT') -DaysOld 400
        Set-TestFileAge -Path (Join-Path -Path $strFolder -ChildPath 'AppData') -DaysOld 400
        Set-TestFileAge -Path $strFolder -DaysOld 400
        $strShort = (New-Object -ComObject Scripting.FileSystemObject).GetFolder($strFolder).ShortPath
        if ($strShort -eq $strFolder) {
            Set-ItResult -Skipped -Because 'The volume has no 8.3 names.'
            return
        }
        @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 1
        New-FakeKey -KeyName 'S-1-5-21-1-2-3-4014' -ImagePath $strShort
        @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 0
    }

    It 'lets a DOMAIN\name exclude pattern protect an orphan folder of that name' {
        $strFolder = Join-Path -Path $script:ProfilesDirectory -ChildPath 'zzpc-orphan-svc'
        [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $strFolder -ChildPath 'AppData'))
        $script:CreatedFolder.Add($strFolder)
        Set-TestFileAge -Path (Join-Path -Path $strFolder -ChildPath 'AppData') -DaysOld 400
        Set-TestFileAge -Path $strFolder -DaysOld 400
        @(Get-UserProfileCleanupItem -MaxAgeDays 90 -IncludeAccount @('zzpc-*') -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 1
        @(Get-UserProfileCleanupItem -MaxAgeDays 90 -IncludeAccount @('zzpc-*') -ExcludeAccount @('CONTOSO\zzpc-orphan-svc') -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 0
    }
}

Describe 'Test-UserProfileSidAllowed' {
    It 'allows user SIDs and rejects well-known and service SIDs' -ForEach @(
        @{ Sid = 'S-1-5-21-1-2-3-1001'; Expected = $true },
        @{ Sid = 'S-1-5-21-1-2-3-1001.bak'; Expected = $true },
        @{ Sid = 'S-1-12-1-111-222-333-444'; Expected = $true },
        @{ Sid = 'S-1-5-21-1-2-3-500'; Expected = $false },
        @{ Sid = 'S-1-5-21-1-2-3-504'; Expected = $false },
        @{ Sid = 'S-1-5-18'; Expected = $false },
        @{ Sid = 'S-1-5-80-1-2-3-4-5'; Expected = $false },
        @{ Sid = ''; Expected = $false }) {
        Test-UserProfileSidAllowed -Sid $Sid | Should -Be $Expected
    }
}

Describe 'Orphan folders' {
    BeforeAll {
        function New-OrphanFolder {
            param ([string]$Name, [double]$DaysOld, [switch]$NoHive)
            $strFolder = Join-Path -Path $script:ProfilesDirectory -ChildPath $Name
            [void][System.IO.Directory]::CreateDirectory((Join-Path -Path $strFolder -ChildPath 'AppData'))
            $script:CreatedFolder.Add($strFolder)
            if (-not $NoHive) {
                $strHive = Join-Path -Path $strFolder -ChildPath 'NTUSER.DAT'
                [System.IO.File]::WriteAllText($strHive, 'x')
                Set-TestFileAge -Path $strHive -DaysOld $DaysOld
            }
            Set-TestFileAge -Path (Join-Path -Path $strFolder -ChildPath 'AppData') -DaysOld $DaysOld
            Set-TestFileAge -Path $strFolder -DaysOld $DaysOld
            return $strFolder
        }
    }

    It 'selects an old profile-shaped folder with no registration' {
        $strFolder = New-OrphanFolder -Name 'zzpc-orphan-old' -DaysOld 120
        $arrItem = @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder })
        $arrItem.Count | Should -Be 1
        $arrItem[0].Basis | Should -Be 'FolderOrHiveWriteTime'
        $null = $arrItem | Remove-UserProfileCleanupItem -Confirm:$false
        Test-Path -LiteralPath $strFolder | Should -BeFalse
    }

    It 'keeps a young orphan folder, so a profile that is being created is safe' {
        $strFolder = New-OrphanFolder -Name 'zzpc-orphan-new' -DaysOld 1
        @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 0
    }

    It 'keeps a folder that is not profile-shaped' {
        $strFolder = Join-Path -Path $script:ProfilesDirectory -ChildPath 'zzpc-orphan-data'
        [void][System.IO.Directory]::CreateDirectory($strFolder)
        $script:CreatedFolder.Add($strFolder)
        Set-TestFileAge -Path $strFolder -DaysOld 300
        @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 0
    }

    It 'keeps a folder that a ProfileList key points to' {
        $strFolder = New-OrphanFolder -Name 'zzpc-orphan-registered' -DaysOld 400
        $strKey = $script:ProfileListPath + '\S-1-5-21-1-2-3-4006'
        [void](New-Item -Path $strKey -Force)
        $script:CreatedKey.Add($strKey)
        Set-ItemProperty -LiteralPath $strKey -Name 'ProfileImagePath' -Value $strFolder
        @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $strFolder }).Count | Should -Be 0
    }

    It 'does not follow a junction out of the folder' {
        $strFolder = New-OrphanFolder -Name 'zzpc-orphan-junction' -DaysOld 120
        $strCanary = Join-Path -Path $TestDrive -ChildPath 'canary'
        [void][System.IO.Directory]::CreateDirectory($strCanary)
        [System.IO.File]::WriteAllText((Join-Path -Path $strCanary -ChildPath 'keep.txt'), 'keep')
        [void](New-Item -ItemType Junction -Path (Join-Path -Path $strFolder -ChildPath 'AppData\LinkToCanary') -Target $strCanary)
        [void](New-Item -ItemType SymbolicLink -Path (Join-Path -Path $strFolder -ChildPath 'LinkToCanary2') -Target $strCanary)
        Remove-UserProfileFolderTree -Path $strFolder
        Test-Path -LiteralPath $strFolder | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $strCanary -ChildPath 'keep.txt') | Should -BeTrue
    }

    It 'removes a real profile folder with its junctions and deny rules' {
        $objProfile = New-TestProfile -Name 'zzpc-orphreal'
        Remove-Item -LiteralPath ($script:ProfileListPath + '\' + $objProfile.Sid) -Recurse -Force
        Set-TestFileAge -Path (Join-Path -Path $objProfile.Path -ChildPath 'NTUSER.DAT') -DaysOld 200
        Set-TestFileAge -Path $objProfile.Path -DaysOld 200
        $arrItem = @(Get-TestItem -Kind 'OrphanFolder' | Where-Object { $_.Path -eq $objProfile.Path })
        $arrItem.Count | Should -Be 1
        $arrResult = @($arrItem | Remove-UserProfileCleanupItem -Confirm:$false)
        $arrResult[0].Succeeded | Should -BeTrue
        Test-Path -LiteralPath $objProfile.Path | Should -BeFalse
        Remove-LocalUser -Name 'zzpc-orphreal'
    }
}

Describe 'Write-UserProfileCleanupLog' {
    It 'creates the folder and appends ASCII lines' {
        $strLog = Join-Path -Path $TestDrive -ChildPath 'sub\test.log'
        Write-UserProfileCleanupLog -LogPath $strLog -Level INFO -Message 'one'
        Write-UserProfileCleanupLog -LogPath $strLog -Level WARN -Message 'two'
        @(Get-Content -LiteralPath $strLog).Count | Should -Be 2
    }

    It 'rolls a file larger than 1 MB' {
        $strLog = Join-Path -Path $TestDrive -ChildPath 'big.log'
        [System.IO.File]::WriteAllText($strLog, ('x' * 1100000))
        Write-UserProfileCleanupLog -LogPath $strLog -Level INFO -Message 'after roll'
        Test-Path -LiteralPath (Join-Path -Path $TestDrive -ChildPath 'big.lo_') | Should -BeTrue
        @(Get-Content -LiteralPath $strLog).Count | Should -Be 1
    }

    It 'does nothing when no path is given' {
        { Write-UserProfileCleanupLog -LogPath '' -Level INFO -Message 'x' } | Should -Not -Throw
    }
}
