#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -RunAsAdministrator

# Run on a lab client, never on a production machine or the dev PC. Most tests use stub
# ConfigMgr cmdlets and make no ConfigMgr change. The last Describe block creates one local
# user named zzpc-pkg with a real profile, runs the staged package content the way a package
# program does (32-bit PowerShell, -File), and removes everything it created.

BeforeAll {
    $script:Folder = Split-Path -Path $PSCommandPath -Parent
    $script:Creator = Join-Path -Path $script:Folder -ChildPath 'New-UserProfileCleanupPackage.ps1'
    $script:ProfileListPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    # The stub cmdlets run under the creator script, where $script: is the creator's own scope.
    # Shared test state therefore lives in global variables.
    $global:UpcPkgCalls = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $global:UpcPkgExisting = $false
    $global:UpcPkgFailProgram = $false

    function Get-CMPackage {
        [CmdletBinding()]
        param ($Name, [switch]$Fast)
        if ($global:UpcPkgExisting) {
            return [pscustomobject]@{ PackageID = 'TST00001' }
        }
        return $null
    }
    function New-CMPackage {
        [CmdletBinding()]
        param ($Name, $Path, $Version, [ValidateLength(0, 127)][string]$Description)
        $global:UpcPkgCalls.Add([pscustomobject]@{ Command = 'New-CMPackage'; Args = @{ Name = $Name; Path = $Path; Version = $Version; Description = $Description } })
        return [pscustomobject]@{ PackageID = 'TST00001' }
    }
    function New-CMProgram {
        [CmdletBinding()]
        param ($PackageName, [ValidateLength(1, 50)][string]$StandardProgramName, $CommandLine, $RunType, $ProgramRunType, $RunMode, $DriveMode, $Duration, $UserInteraction)
        if ($global:UpcPkgFailProgram) {
            throw 'program failed (test)'
        }
        $hashtableBound = @{}
        foreach ($strKey in $PSBoundParameters.Keys) {
            $hashtableBound[$strKey] = $PSBoundParameters[$strKey]
        }
        $global:UpcPkgCalls.Add([pscustomobject]@{ Command = 'New-CMProgram'; Args = $hashtableBound })
    }
    function Start-CMContentDistribution {
        [CmdletBinding()]
        param ($PackageName, $DistributionPointGroupName, $DistributionPointName)
        $hashtableBound = @{}
        foreach ($strKey in $PSBoundParameters.Keys) {
            $hashtableBound[$strKey] = $PSBoundParameters[$strKey]
        }
        $global:UpcPkgCalls.Add([pscustomobject]@{ Command = 'Start-CMContentDistribution'; Args = $hashtableBound })
    }
    function New-CMSchedule {
        [CmdletBinding()]
        param ($RecurInterval, $RecurCount)
        $global:UpcPkgCalls.Add([pscustomobject]@{ Command = 'New-CMSchedule'; Args = @{ RecurInterval = $RecurInterval; RecurCount = $RecurCount } })
        return [pscustomobject]@{ Schedule = 'stub' }
    }
    function New-CMPackageDeployment {
        [CmdletBinding()]
        param ([switch]$StandardProgram, $PackageName, $ProgramName, $CollectionName, $DeployPurpose, $Schedule, $RerunBehavior, $SendWakeupPacket, $FastNetworkOption, $SlowNetworkOption, $SoftwareInstallation)
        $hashtableBound = @{}
        foreach ($strKey in $PSBoundParameters.Keys) {
            $hashtableBound[$strKey] = $PSBoundParameters[$strKey]
        }
        $global:UpcPkgCalls.Add([pscustomobject]@{ Command = 'New-CMPackageDeployment'; Args = $hashtableBound })
    }
    function Remove-CMPackage {
        [CmdletBinding()]
        param ($Name, $Id, [switch]$Force)
        $global:UpcPkgCalls.Add([pscustomobject]@{ Command = 'Remove-CMPackage'; Args = @{ Name = $Name; Id = $Id } })
    }
    function Get-Call {
        param ([string]$Command)
        return ,@($global:UpcPkgCalls | Where-Object { $_.Command -eq $Command })
    }

    if (-not ('UpcPkg.Native' -as [type])) {
        Add-Type -Namespace UpcPkg -Name Native -MemberDefinition @'
[DllImport("userenv.dll", CharSet=CharSet.Unicode)]
public static extern int CreateProfile([MarshalAs(UnmanagedType.LPWStr)] string pszUserSid, [MarshalAs(UnmanagedType.LPWStr)] string pszUserName, System.Text.StringBuilder pszProfilePath, uint cchProfilePath);
'@
    }
}

AfterAll {
    foreach ($strName in @('UpcPkgCalls', 'UpcPkgExisting', 'UpcPkgFailProgram', 'UpcPkgAnswers')) {
        Remove-Variable -Name $strName -Scope Global -ErrorAction SilentlyContinue
    }
}

Describe 'New-UserProfileCleanupPackage with stub ConfigMgr cmdlets' {
    BeforeEach {
        $global:UpcPkgCalls.Clear()
        $global:UpcPkgExisting = $false
        $global:UpcPkgFailProgram = $false
        $script:Source = Join-Path -Path $TestDrive -ChildPath ('src-{0}' -f [guid]::NewGuid().ToString('N'))
    }

    Context 'Staging' {
        It 'writes the runner, the engine and a generated wrapper and makes no ConfigMgr call' {
            & $script:Creator -StageOnly -SourcePath $script:Source -Days 60 -ExcludeAccounts @("o'brien*", 'svc_*')
            foreach ($strFile in @('Invoke-UserProfileCleanup.ps1', 'UserProfileCleanup.Engine.ps1', 'Run-UserProfileCleanup.ps1')) {
                Test-Path -LiteralPath (Join-Path -Path $script:Source -ChildPath $strFile) | Should -BeTrue
            }
            Test-Path -LiteralPath (Join-Path -Path $script:Source -ChildPath 'UserProfileCleanup.Engine.Tests.ps1') | Should -BeFalse
            $global:UpcPkgCalls.Count | Should -Be 0
        }

        It 'generates a parseable ASCII wrapper that carries the settings' {
            & $script:Creator -StageOnly -SourcePath $script:Source -Days 60 -ExcludeAccounts @("o'brien*", 'svc_*') -DetectOnly -Scope @('StaleProfile')
            $strText = [System.IO.File]::ReadAllText((Join-Path -Path $script:Source -ChildPath 'Run-UserProfileCleanup.ps1'))
            $arrError = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($strText, [ref]$null, [ref]$arrError)
            $arrError.Count | Should -Be 0
            $strText | Should -Not -Match '[^\x00-\x7F]'
            $strText | Should -BeLike '*-Days 60*'
            $strText | Should -BeLike "*-ExcludeAccounts @('o''brien*', 'svc_*')*"
            $strText | Should -BeLike "*-Scope @('StaleProfile')*"
            $strText | Should -BeLike '*-DetectOnly*'
            $strText | Should -BeLike '*exit $LASTEXITCODE*'
        }

        It 'refuses a pattern that is not printable ASCII or not a valid wildcard' {
            { & $script:Creator -StageOnly -SourcePath $script:Source -Days 60 -ExcludeAccounts @('svc_[') } | Should -Throw '*not a valid wildcard*'
            { & $script:Creator -StageOnly -SourcePath $script:Source -Days 60 -ExcludeAccounts @(('jos' + [char]0x00E9)) } | Should -Throw '*not printable ASCII*'
        }
    }

    Context 'Staging safety' {
        It 'refuses a folder that holds the wrapper of a package with other settings, and changes nothing' {
            & $script:Creator -StageOnly -SourcePath $script:Source -Days 90
            $strWrapper = Join-Path -Path $script:Source -ChildPath 'Run-UserProfileCleanup.ps1'
            $strBefore = [System.IO.File]::ReadAllText($strWrapper)
            { & $script:Creator -StageOnly -SourcePath $script:Source -Days 60 } | Should -Throw '*other settings*'
            [System.IO.File]::ReadAllText($strWrapper) | Should -BeExactly $strBefore
        }

        It 'accepts the same settings twice, and refreshes the scripts' {
            & $script:Creator -StageOnly -SourcePath $script:Source -Days 90
            { & $script:Creator -StageOnly -SourcePath $script:Source -Days 90 } | Should -Not -Throw
        }

        It 'does not stage content when the package already exists' {
            $global:UpcPkgExisting = $true
            { & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 } | Should -Throw '*already exists*'
            Test-Path -LiteralPath $script:Source | Should -BeFalse
        }

        It 'works when the source folder is the folder of the scripts' {
            $strScripts = Join-Path -Path $TestDrive -ChildPath 'scripts'
            [void][System.IO.Directory]::CreateDirectory($strScripts)
            foreach ($strFile in @('New-UserProfileCleanupPackage.ps1', 'Invoke-UserProfileCleanup.ps1', 'UserProfileCleanup.Engine.ps1')) {
                Copy-Item -LiteralPath (Join-Path -Path $script:Folder -ChildPath $strFile) -Destination $strScripts
            }
            { & (Join-Path -Path $strScripts -ChildPath 'New-UserProfileCleanupPackage.ps1') -StageOnly -SourcePath $strScripts -Days 90 } | Should -Not -Throw
            Test-Path -LiteralPath (Join-Path -Path $strScripts -ChildPath 'Run-UserProfileCleanup.ps1') | Should -BeTrue
        }

        It 'returns exit code 2 from the wrapper when the runner is missing' {
            & $script:Creator -StageOnly -SourcePath $script:Source -Days 90
            Remove-Item -LiteralPath (Join-Path -Path $script:Source -ChildPath 'Invoke-UserProfileCleanup.ps1') -Force
            $strPowerShell = Join-Path -Path $env:windir -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $null = & $strPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path -Path $script:Source -ChildPath 'Run-UserProfileCleanup.ps1') 2>&1
            $LASTEXITCODE | Should -Be 2
        }
    }

    Context 'Day count' {
        It 'asks until the answer is valid and puts it in the names' {
            $global:UpcPkgAnswers = New-Object -TypeName 'System.Collections.Generic.Queue[string]'
            foreach ($strAnswer in @('x', '0', '45')) {
                $global:UpcPkgAnswers.Enqueue($strAnswer)
            }
            Mock Read-Host { $global:UpcPkgAnswers.Dequeue() }
            Mock Write-Warning { }
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source
            (Get-Call 'New-CMPackage')[0].Args.Name | Should -Be 'Maintenance: User Profile Cleanup (Package) - 45 Days'
        }

        It 'puts <Days> in the package and program names' -ForEach @(@{ Days = 30 }, @{ Days = 90 }, @{ Days = 365 }) {
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days $Days
            (Get-Call 'New-CMPackage')[0].Args.Name | Should -Be ('Maintenance: User Profile Cleanup (Package) - {0} Days' -f $Days)
            (Get-Call 'New-CMProgram')[0].Args.StandardProgramName | Should -Be ('Clean up user profiles ({0} days)' -f $Days)
            (Get-Call 'New-CMPackage')[0].Args.Description.Length | Should -BeLessOrEqual 127
        }
    }

    Context 'ConfigMgr objects' {
        It 'creates a hidden program with administrative rights that runs whether or not a user is signed in' {
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90
            $hashtableProgram = (Get-Call 'New-CMProgram')[0].Args
            $hashtableProgram.CommandLine | Should -Be 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Run-UserProfileCleanup.ps1'
            $hashtableProgram.RunType | Should -Be 'Hidden'
            $hashtableProgram.ProgramRunType | Should -Be 'WhetherOrNotUserIsLoggedOn'
            $hashtableProgram.RunMode | Should -Be 'RunWithAdministrativeRights'
            $hashtableProgram.CommandLine.Length | Should -BeLessThan 255
            (Get-Call 'New-CMPackage')[0].Args.Path | Should -Be $script:Source
        }

        It 'does not distribute or deploy by default' {
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90
            (Get-Call 'Start-CMContentDistribution').Count | Should -Be 0
            (Get-Call 'New-CMPackageDeployment').Count | Should -Be 0
        }

        It 'distributes to the given distribution point group' {
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 -DistributionPointGroupName 'All DPs'
            $hashtableDistribution = (Get-Call 'Start-CMContentDistribution')[0].Args
            $hashtableDistribution.DistributionPointGroupName | Should -Be 'All DPs'
            $hashtableDistribution.PackageName | Should -BeLike '*90 Days'
        }

        It 'creates a required, recurring, always-rerun deployment when a collection is given' {
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 -CollectionName 'Test Collection' -ScheduleDays 3
            $hashtableDeployment = (Get-Call 'New-CMPackageDeployment')[0].Args
            $hashtableDeployment.CollectionName | Should -Be 'Test Collection'
            $hashtableDeployment.DeployPurpose | Should -Be 'Required'
            $hashtableDeployment.RerunBehavior | Should -Be 'AlwaysRerunProgram'
            $hashtableDeployment.StandardProgram | Should -BeTrue
            (Get-Call 'New-CMSchedule')[0].Args.RecurInterval | Should -Be 'Days'
            (Get-Call 'New-CMSchedule')[0].Args.RecurCount | Should -Be 3
        }

        It 'honors maintenance windows unless told otherwise' {
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 -CollectionName 'Test Collection'
            (Get-Call 'New-CMPackageDeployment')[0].Args.ContainsKey('SoftwareInstallation') | Should -BeFalse
            $global:UpcPkgCalls.Clear()
            & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 -CollectionName 'Test Collection' -RunOutsideMaintenanceWindow
            (Get-Call 'New-CMPackageDeployment')[0].Args.SoftwareInstallation | Should -BeTrue
        }

        It 'stops before it creates anything when the package exists' {
            $global:UpcPkgExisting = $true
            { & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 } | Should -Throw '*already exists*'
            (Get-Call 'New-CMPackage').Count | Should -Be 0
            (Get-Call 'Remove-CMPackage').Count | Should -Be 0
            Test-Path -LiteralPath $script:Source | Should -BeFalse
        }

        It 'removes the package it created when a later step fails' {
            $global:UpcPkgFailProgram = $true
            Mock Write-Warning { }
            { & $script:Creator -SiteCode TST -SiteServer srv.test -AssumeConnected -SourcePath $script:Source -Days 90 } | Should -Throw '*program failed*'
            (Get-Call 'Remove-CMPackage').Count | Should -Be 1
            (Get-Call 'Remove-CMPackage')[0].Args.Id | Should -Be 'TST00001'
        }
    }
}

Describe 'Staged package content on a real profile' {
    BeforeAll {
        $script:Source = Join-Path -Path $TestDrive -ChildPath 'real'
        $script:CCMLog = Join-Path -Path $env:windir -ChildPath 'CCM\Logs\UserProfileCleanup.log'
        $script:CCMLogExisted = Test-Path -LiteralPath $script:CCMLog
        $strName = 'zzpc-pkg'
        $objPassword = ConvertTo-SecureString -String ([guid]::NewGuid().ToString('N') + 'Aa1!') -AsPlainText -Force
        [void](New-LocalUser -Name $strName -Password $objPassword -AccountNeverExpires)
        $script:Sid = (Get-LocalUser -Name $strName).SID.Value
        $objPath = New-Object -TypeName System.Text.StringBuilder -ArgumentList 260
        $intResult = [UpcPkg.Native]::CreateProfile($script:Sid, $strName, $objPath, 260)
        if ($intResult -ne 0) {
            throw ('CreateProfile failed: 0x{0:X8}' -f $intResult)
        }
        $script:ProfilePath = $objPath.ToString()
        $longFileTime = [datetime]::UtcNow.AddDays(-100).ToFileTimeUtc()
        $strKey = $script:ProfileListPath + '\' + $script:Sid
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeLow' -Type DWord `
            -Value ([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -band 0xFFFFFFFFL)), 0))
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeHigh' -Type DWord `
            -Value ([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -shr 32)), 0))
        & $script:Creator -StageOnly -SourcePath $script:Source -Days 90 -IncludeAccounts @('zzpc-pkg*')
    }

    It 'runs the program command line with the 32-bit PowerShell, as a package program does, and removes the profile' {
        $strPowerShell = Join-Path -Path $env:windir -ChildPath 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $strPowerShell)) {
            $strPowerShell = Join-Path -Path $env:windir -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
        }
        Push-Location -LiteralPath $script:Source
        try {
            $arrOutput = @(& $strPowerShell -NoProfile -ExecutionPolicy Bypass -File .\Run-UserProfileCleanup.ps1 2>&1 | ForEach-Object { "$_" })
            $intExit = $LASTEXITCODE
        } finally {
            Pop-Location
        }
        $intExit | Should -Be 0
        ($arrOutput -join "`n") | Should -BeLike '*Found 1, removed 1, failed 0*'
        Test-Path -LiteralPath $script:ProfilePath | Should -BeFalse
        Test-Path -LiteralPath ($script:ProfileListPath + '\' + $script:Sid) | Should -BeFalse
        [System.IO.File]::ReadAllText($script:CCMLog) | Should -BeLike '*Done: found 1, removed 1, failed 0*'
    }

    AfterAll {
        $objUser = Get-LocalUser -Name 'zzpc-pkg' -ErrorAction SilentlyContinue
        if ($objUser) {
            $objCim = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID = '{0}'" -f $objUser.SID.Value)
            if ($objCim) {
                Remove-CimInstance -InputObject $objCim
            }
            Remove-LocalUser -Name 'zzpc-pkg'
        }
        if (($null -ne $script:ProfilePath) -and (Test-Path -LiteralPath $script:ProfilePath)) {
            Remove-Item -LiteralPath $script:ProfilePath -Recurse -Force
        }
        if ((-not $script:CCMLogExisted) -and (Test-Path -LiteralPath $script:CCMLog)) {
            Remove-Item -LiteralPath $script:CCMLog -Force
        }
    }
}
