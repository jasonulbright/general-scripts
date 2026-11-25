#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
#Requires -RunAsAdministrator

# Run on a lab client, never on a production machine or the dev PC. The generator tests use
# stub ConfigMgr cmdlets and make no ConfigMgr change. The last Describe block creates one
# local user named zzpc-gen with a real profile, runs the generated scripts on it, and
# removes everything it created.

BeforeAll {
    $strScriptFolder = Split-Path -Path $PSCommandPath -Parent
    $script:Generator = Join-Path -Path $strScriptFolder -ChildPath 'New-UserProfileCleanupBaseline.ps1'
    # The stub cmdlets run under the generator script, where $script: is the generator's own scope.
    # Shared test state therefore lives in global variables.
    $global:UpcTestCalls = New-Object -TypeName 'System.Collections.Generic.List[object]'
    $global:UpcTestExistingCI = $false
    $global:UpcTestExistingCB = $false
    $global:UpcTestCICreated = $false
    $global:UpcTestFailBaseline = $false
    $script:CCMLog = Join-Path -Path $env:windir -ChildPath 'CCM\Logs\UserProfileCleanup.log'
    $script:CCMLogExisted = Test-Path -LiteralPath $script:CCMLog

    function Get-CMConfigurationItem {
        [CmdletBinding()]
        param ($Name, [switch]$Fast)
        if ($global:UpcTestExistingCI -or $global:UpcTestCICreated) {
            return [pscustomobject]@{ CI_ID = 77; LocalizedDisplayName = $Name }
        }
        return $null
    }
    function Get-CMBaseline {
        [CmdletBinding()]
        param ($Name, [switch]$Fast)
        if ($global:UpcTestExistingCB) {
            return [pscustomobject]@{ CI_ID = 88 }
        }
        return $null
    }
    function New-CMConfigurationItem {
        [CmdletBinding()]
        param ($Name, $Description, $CreationType)
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'New-CMConfigurationItem'; Args = @{ Name = $Name; Description = $Description; CreationType = $CreationType } })
        $global:UpcTestCICreated = $true
        return [pscustomobject]@{ CI_ID = 77 }
    }
    function Add-CMComplianceSettingScript {
        [CmdletBinding()]
        param ($InputObject, $Name, $Description, $DataType, $DiscoveryScriptLanguage, $DiscoveryScriptText,
            [switch]$Is64Bit, [switch]$ValueRule, $RuleName, $RuleDescription, $ExpressionOperator, $ExpectedValue,
            $NoncomplianceSeverity, [switch]$ReportNoncompliance, $RemediationScriptLanguage, $RemediationScriptText,
            [switch]$Remediate)
        $hashtableBound = @{}
        foreach ($strKey in $PSBoundParameters.Keys) {
            $hashtableBound[$strKey] = $PSBoundParameters[$strKey]
        }
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'Add-CMComplianceSettingScript'; Args = $hashtableBound })
    }
    function New-CMBaseline {
        [CmdletBinding()]
        param ($Name, $Description)
        if ($global:UpcTestFailBaseline) {
            throw 'baseline failed (test)'
        }
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'New-CMBaseline'; Args = @{ Name = $Name; Description = $Description } })
    }
    function Remove-CMBaseline {
        [CmdletBinding()]
        param ($Name, [switch]$Force)
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'Remove-CMBaseline'; Args = @{ Name = $Name } })
    }
    function Remove-CMConfigurationItem {
        [CmdletBinding()]
        param ($Name, [switch]$Force)
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'Remove-CMConfigurationItem'; Args = @{ Name = $Name } })
    }
    function Set-CMBaseline {
        [CmdletBinding()]
        param ($Name, $AddOSConfigurationItem)
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'Set-CMBaseline'; Args = @{ Name = $Name; AddOSConfigurationItem = $AddOSConfigurationItem } })
    }
    function New-CMSchedule {
        [CmdletBinding()]
        param ($RecurInterval, $RecurCount)
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'New-CMSchedule'; Args = @{ RecurInterval = $RecurInterval; RecurCount = $RecurCount } })
        return [pscustomobject]@{ Schedule = 'stub' }
    }
    function New-CMBaselineDeployment {
        [CmdletBinding()]
        param ($Name, $CollectionName, $EnableEnforcement, $OverrideServiceWindow, $GenerateAlert, $MonitoredByScom, $Schedule)
        $hashtableBound = @{}
        foreach ($strKey in $PSBoundParameters.Keys) {
            $hashtableBound[$strKey] = $PSBoundParameters[$strKey]
        }
        $global:UpcTestCalls.Add([pscustomobject]@{ Command = 'New-CMBaselineDeployment'; Args = $hashtableBound })
    }

    function Invoke-ScriptFile {
        param ([string]$Path)
        return @(& ([scriptblock]::Create([System.IO.File]::ReadAllText($Path))))
    }

    function Get-Call {
        param ([string]$Command)
        return ,@($global:UpcTestCalls | Where-Object { $_.Command -eq $Command })
    }

    if (-not ('UpcGenTest.Native' -as [type])) {
        Add-Type -Namespace UpcGenTest -Name Native -MemberDefinition @'
[DllImport("userenv.dll", CharSet=CharSet.Unicode)]
public static extern int CreateProfile([MarshalAs(UnmanagedType.LPWStr)] string pszUserSid, [MarshalAs(UnmanagedType.LPWStr)] string pszUserName, System.Text.StringBuilder pszProfilePath, uint cchProfilePath);
'@
    }
}

AfterAll {
    foreach ($strName in @('UpcTestCalls', 'UpcTestExistingCI', 'UpcTestExistingCB', 'UpcTestCICreated', 'UpcTestAnswers', 'UpcTestFailBaseline')) {
        Remove-Variable -Name $strName -Scope Global -ErrorAction SilentlyContinue
    }
    if ((-not $script:CCMLogExisted) -and (Test-Path -LiteralPath $script:CCMLog)) {
        Remove-Item -LiteralPath $script:CCMLog -Force
    }
}

Describe 'New-UserProfileCleanupBaseline with stub ConfigMgr cmdlets' {
    BeforeEach {
        $global:UpcTestCalls.Clear()
        $global:UpcTestExistingCI = $false
        $global:UpcTestExistingCB = $false
        $global:UpcTestCICreated = $false
        $global:UpcTestFailBaseline = $false
    }

    Context 'Names carry the day count' {
        It 'puts <Days> in both names' -ForEach @(
            @{ Days = 30 }, @{ Days = 60 }, @{ Days = 90 }, @{ Days = 365 }) {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days $Days
            (Get-Call 'New-CMConfigurationItem')[0].Args.Name | Should -Be ('Maintenance: User Profile Cleanup - {0} Days' -f $Days)
            (Get-Call 'New-CMBaseline')[0].Args.Name | Should -Be ('Maintenance User Profile Cleanup - {0} Days' -f $Days)
            (Get-Call 'Set-CMBaseline')[0].Args.Name | Should -Be ('Maintenance User Profile Cleanup - {0} Days' -f $Days)
        }

        It 'keeps the day count in the compliance rule name' {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 45
            (Get-Call 'Add-CMComplianceSettingScript')[0].Args.RuleName | Should -BeLike '*45 days*'
        }
    }

    Context 'Day count prompt' {
        It 'asks until the answer is a valid number, then uses it' {
            $global:UpcTestAnswers = New-Object -TypeName 'System.Collections.Generic.Queue[string]'
            foreach ($strAnswer in @('abc', '0', '99999', ' 45 ')) {
                $global:UpcTestAnswers.Enqueue($strAnswer)
            }
            Mock Read-Host { $global:UpcTestAnswers.Dequeue() }
            Mock Write-Warning { }
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected
            (Get-Call 'New-CMConfigurationItem')[0].Args.Name | Should -Be 'Maintenance: User Profile Cleanup - 45 Days'
            Should -Invoke Read-Host -Times 4 -Exactly
            Should -Invoke Write-Warning -Times 3 -Exactly
        }

        It 'does not ask when -Days is given' {
            Mock Read-Host { throw 'must not prompt' }
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 60 } | Should -Not -Throw
        }

        It 'stops with a clear message when the host cannot prompt' {
            Mock Read-Host { throw 'no console' }
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected } | Should -Throw '*Pass -Days*'
            (Get-Call 'New-CMConfigurationItem').Count | Should -Be 0
        }

        It 'rejects a day count outside 1 to 3650 at parameter binding' {
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 0 } | Should -Throw
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 4000 } | Should -Throw
        }
    }

    Context 'ConfigMgr objects' {
        It 'removes what it created when a later step fails' {
            $global:UpcTestFailBaseline = $true
            Mock Write-Warning { }
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90 } | Should -Throw '*baseline failed*'
            (Get-Call 'Remove-CMConfigurationItem').Count | Should -Be 1
            (Get-Call 'Remove-CMConfigurationItem')[0].Args.Name | Should -Be 'Maintenance: User Profile Cleanup - 90 Days'
            (Get-Call 'Remove-CMBaseline').Count | Should -Be 0
        }

        It 'removes nothing when the CI already exists' {
            $global:UpcTestExistingCI = $true
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90 } | Should -Throw '*already exists*'
            (Get-Call 'Remove-CMConfigurationItem').Count | Should -Be 0
        }

        It 'creates an Integer script setting with an equals-0 rule, 64-bit and remediation' {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90
            $hashtableSetting = (Get-Call 'Add-CMComplianceSettingScript')[0].Args
            $hashtableSetting.DataType | Should -Be 'Integer'
            $hashtableSetting.ValueRule | Should -BeTrue
            $hashtableSetting.ExpressionOperator | Should -Be 'IsEquals'
            $hashtableSetting.ExpectedValue | Should -Be '0'
            $hashtableSetting.Is64Bit | Should -BeTrue
            $hashtableSetting.Remediate | Should -BeTrue
            $hashtableSetting.DiscoveryScriptLanguage | Should -Be 'PowerShell'
            $hashtableSetting.RemediationScriptLanguage | Should -Be 'PowerShell'
            $hashtableSetting.DiscoveryScriptText | Should -BeLike '*-MaxAgeDays 90*'
            $hashtableSetting.RemediationScriptText | Should -BeLike '*-MaxAgeDays 90*'
            $hashtableSetting.RemediationScriptText | Should -BeLike '*Remove-UserProfileCleanupItem*'
            $hashtableSetting.DiscoveryScriptText | Should -Not -BeLike '*Remove-UserProfileCleanupItem -*'
        }

        It 'adds the CI to the baseline by CI id' {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90
            (Get-Call 'Set-CMBaseline')[0].Args.AddOSConfigurationItem | Should -Be 77
        }

        It 'does not deploy without a collection' {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90
            (Get-Call 'New-CMBaselineDeployment').Count | Should -Be 0
        }

        It 'deploys with enforcement and the schedule when a collection is given' {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90 -CollectionName 'Test Collection' -ScheduleDays 3
            $hashtableDeployment = (Get-Call 'New-CMBaselineDeployment')[0].Args
            $hashtableDeployment.CollectionName | Should -Be 'Test Collection'
            $hashtableDeployment.EnableEnforcement | Should -BeTrue
            (Get-Call 'New-CMSchedule')[0].Args.RecurCount | Should -Be 3
        }

        It 'has no remediation and no enforcement with -DetectOnly' {
            & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90 -DetectOnly -CollectionName 'Test Collection'
            $hashtableSetting = (Get-Call 'Add-CMComplianceSettingScript')[0].Args
            $hashtableSetting.ContainsKey('Remediate') | Should -BeFalse
            $hashtableSetting.ContainsKey('RemediationScriptText') | Should -BeFalse
            (Get-Call 'New-CMBaselineDeployment')[0].Args.EnableEnforcement | Should -BeFalse
        }

        It 'stops before it creates anything when the CI exists' {
            $global:UpcTestExistingCI = $true
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90 } | Should -Throw '*already exists*'
            (Get-Call 'New-CMConfigurationItem').Count | Should -Be 0
        }

        It 'stops before it creates anything when the baseline exists' {
            $global:UpcTestExistingCB = $true
            { & $script:Generator -SiteCode TST -SiteServer srv.test -AssumeConnected -Days 90 } | Should -Throw '*already exists*'
            (Get-Call 'New-CMConfigurationItem').Count | Should -Be 0
        }
    }
}

Describe 'Generated script text' {
    BeforeAll {
        $global:UpcTestCalls.Clear()
        $script:OutputFolder = Join-Path -Path $TestDrive -ChildPath 'scripts'
        & $script:Generator -ScriptOnly -OutputFolder $script:OutputFolder -Days 90 `
            -ExcludeAccounts @("o'brien*", 'svc_*') -IncludeAccounts @('*') -Scope @('StaleProfile', 'OrphanFolder')
        $script:DiscoveryText = [System.IO.File]::ReadAllText((Join-Path -Path $script:OutputFolder -ChildPath 'UserProfileCleanup-Discovery-90Days.ps1'))
        $script:RemediationText = [System.IO.File]::ReadAllText((Join-Path -Path $script:OutputFolder -ChildPath 'UserProfileCleanup-Remediation-90Days.ps1'))
    }

    It 'writes scripts named for the day count and makes no ConfigMgr call' {
        (Get-Call 'New-CMConfigurationItem').Count | Should -Be 0
    }

    It 'parses without error' -ForEach @(@{ Which = 'DiscoveryText' }, @{ Which = 'RemediationText' }) {
        $arrError = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput((Get-Variable -Scope Script -Name $Which).Value, [ref]$null, [ref]$arrError)
        $arrError.Count | Should -Be 0
    }

    It 'is plain ASCII with CRLF line endings and no comment lines' -ForEach @(@{ Which = 'DiscoveryText' }, @{ Which = 'RemediationText' }) {
        $strText = (Get-Variable -Scope Script -Name $Which).Value
        $strText | Should -Not -Match '[^\x00-\x7F]'
        $strText | Should -Not -Match '(?<!\r)\n'
        $strText | Should -Not -Match '(?m)^\s*#'
    }

    It 'quotes patterns and passes the settings' {
        $script:DiscoveryText | Should -BeLike "*-ExcludeAccount @('o''brien*', 'svc_*')*"
        $script:DiscoveryText | Should -BeLike "*-IncludeAccount @('*')*"
        $script:DiscoveryText | Should -BeLike "*-Kind @('StaleProfile', 'OrphanFolder')*"
    }

    It 'ends discovery with a call that outputs the item count' {
        ($script:DiscoveryText.TrimEnd() -split "\r\n")[-1] | Should -BeLike '[[]int]@(Get-UserProfileCleanupItem -MaxAgeDays 90*).Count'
    }

    It 'rejects a pattern that is not printable ASCII' -ForEach @(
        @{ Pattern = "a`nb" },
        @{ Pattern = ([string][char]0x2019 + 'x*') },
        @{ Pattern = ('jos' + [char]0x00E9 + '*') }) {
        { & $script:Generator -ScriptOnly -OutputFolder $script:OutputFolder -Days 90 -ExcludeAccounts @($Pattern) } | Should -Throw '*not printable ASCII*'
    }

    It 'rejects an invalid wildcard pattern before any script is written' {
        $strFolder = Join-Path -Path $TestDrive -ChildPath 'badpattern'
        { & $script:Generator -ScriptOnly -OutputFolder $strFolder -Days 90 -ExcludeAccounts @('svc_[') } | Should -Throw '*not a valid wildcard*'
        Test-Path -LiteralPath (Join-Path -Path $strFolder -ChildPath 'UserProfileCleanup-Discovery-90Days.ps1') | Should -BeFalse
    }
}

Describe 'Generated scripts on a real profile' {
    BeforeAll {
        $script:OutputFolder = Join-Path -Path $TestDrive -ChildPath 'run'
        $strName = 'zzpc-gen'
        $objPassword = ConvertTo-SecureString -String ([guid]::NewGuid().ToString('N') + 'Aa1!') -AsPlainText -Force
        [void](New-LocalUser -Name $strName -Password $objPassword -AccountNeverExpires)
        $script:GenSid = (Get-LocalUser -Name $strName).SID.Value
        $objPath = New-Object -TypeName System.Text.StringBuilder -ArgumentList 260
        $intResult = [UpcGenTest.Native]::CreateProfile($script:GenSid, $strName, $objPath, 260)
        if ($intResult -ne 0) {
            throw ('CreateProfile failed: 0x{0:X8}' -f $intResult)
        }
        $script:GenPath = $objPath.ToString()
        $longFileTime = [datetime]::UtcNow.AddDays(-100).ToFileTimeUtc()
        $strKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $script:GenSid
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeLow' -Type DWord `
            -Value ([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -band 0xFFFFFFFFL)), 0))
        Set-ItemProperty -LiteralPath $strKey -Name 'LocalProfileUnLoadTimeHigh' -Type DWord `
            -Value ([BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]($longFileTime -shr 32)), 0))
    }

    It 'discovery returns one Int32 for the stale test profile and 0 for a 200-day limit' {
        & $script:Generator -ScriptOnly -OutputFolder $script:OutputFolder -Days 90 -IncludeAccounts @('zzpc-gen*')
        $strDiscovery = Join-Path -Path $script:OutputFolder -ChildPath 'UserProfileCleanup-Discovery-90Days.ps1'
        $arrOutput = Invoke-ScriptFile -Path $strDiscovery
        $arrOutput.Count | Should -Be 1
        $arrOutput[0] | Should -BeOfType [int]
        $arrOutput[0] | Should -Be 1

        & $script:Generator -ScriptOnly -OutputFolder $script:OutputFolder -Days 200 -IncludeAccounts @('zzpc-gen*')
        $arrOutput = Invoke-ScriptFile -Path (Join-Path -Path $script:OutputFolder -ChildPath 'UserProfileCleanup-Discovery-200Days.ps1')
        $arrOutput[0] | Should -Be 0
    }

    It 'discovery returns 0 for an include pattern that matches nothing' {
        & $script:Generator -ScriptOnly -OutputFolder $script:OutputFolder -Days 1 -IncludeAccounts @('zzpc-nomatch-*')
        $arrOutput = Invoke-ScriptFile -Path (Join-Path -Path $script:OutputFolder -ChildPath 'UserProfileCleanup-Discovery-1Days.ps1')
        $arrOutput.Count | Should -Be 1
        $arrOutput[0] | Should -Be 0
    }

    It 'remediation removes the profile, writes the log and produces no output' {
        & $script:Generator -ScriptOnly -OutputFolder $script:OutputFolder -Days 90 -IncludeAccounts @('zzpc-gen*')
        $arrOutput = Invoke-ScriptFile -Path (Join-Path -Path $script:OutputFolder -ChildPath 'UserProfileCleanup-Remediation-90Days.ps1')
        $arrOutput.Count | Should -Be 0
        Test-Path -LiteralPath $script:GenPath | Should -BeFalse
        Test-Path -LiteralPath ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\' + $script:GenSid) | Should -BeFalse
        $strLog = [System.IO.File]::ReadAllText($script:CCMLog)
        $strLog | Should -BeLike '*Pass 1: 1 item(s)*'
        $strLog | Should -BeLike '*StaleProfile*zzpc-gen*Profile removed*'
        $strLog | Should -BeLike '*Pass 2: 0 item(s)*'
    }

    AfterAll {
        $objUser = Get-LocalUser -Name 'zzpc-gen' -ErrorAction SilentlyContinue
        if ($objUser) {
            $objCim = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID = '{0}'" -f $objUser.SID.Value)
            if ($objCim) {
                Remove-CimInstance -InputObject $objCim
            }
            Remove-LocalUser -Name 'zzpc-gen'
        }
        if (($null -ne $script:GenPath) -and (Test-Path -LiteralPath $script:GenPath)) {
            Remove-Item -LiteralPath $script:GenPath -Recurse -Force
        }
    }
}
