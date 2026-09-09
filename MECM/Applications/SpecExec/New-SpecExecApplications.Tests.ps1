#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }
BeforeAll {
    $script:creator = Join-Path $PSScriptRoot 'New-SpecExecApplications.ps1'
    . $script:creator -ContentOnly -ContentRoot $TestDrive

    # Load only the GUI's arithmetic function; never load WPF or show the GUI.
    $guiAst = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot '..\..\..\Registry\New-SpecExecBitmask.ps1'), [ref]$null, [ref]$null)
    $stateFunction = $guiAst.Find({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-State'
    }, $true)
    . ([scriptblock]::Create($stateFunction.Extent.Text))

    function New-FakeRegistry {
        $base = [pscustomobject]@{ Keys = @{}; FailWrite = $false; FailReadBack = $false; Disposed = $false }
        $base | Add-Member ScriptMethod CreateSubKey {
            param($path)
            if (-not $this.Keys.ContainsKey($path)) {
                $key = [pscustomobject]@{ Parent = $this; Values = @{}; Kinds = @{}; Disposed = $false }
                $key | Add-Member ScriptMethod SetValue {
                    param($name, $value, $kind)
                    if ($this.Parent.FailWrite) { throw 'Access denied (test)' }
                    $this.Values[$name] = $value; $this.Kinds[$name] = $kind
                }
                $key | Add-Member ScriptMethod GetValue {
                    param($name)
                    if ($this.Parent.FailReadBack) { return 'Wrong value' }
                    return $this.Values[$name]
                }
                $key | Add-Member ScriptMethod GetValueKind { param($name) return $this.Kinds[$name] }
                $key | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
                $this.Keys[$path] = $key
            }
            return $this.Keys[$path]
        }
        $base | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
        return $base
    }

    function Invoke-FakeInstaller {
        param($Profile, $FakeBase)
        $text = New-SpecExecInstallerText -Profile $Profile
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        $open = @($ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $n.Member.Extent.Text -eq 'OpenBaseKey'
        }, $true))
        if ($open.Count -ne 1) { throw 'Expected exactly one registry-open expression to substitute.' }
        $exit = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.ExitStatementAst] }, $true)
        # Only replace the registry handle and process exit; run the actual payload.
        $safe = $text.Replace($open[0].Extent.Text, '$FakeBase').Replace($exit.Extent.Text, 'return $result')
        if ($safe -match 'OpenBaseKey|Restart-Computer') { throw 'Unsafe test payload.' }
        return @(& ([scriptblock]::Create($safe)))
    }

    function Get-CMApplication { [CmdletBinding()]param($Name, [switch]$DisableWildcardHandling) }
    # Match the real cmdlet: there is NO ApplicationId parameter on Get.
    function Get-CMDeploymentType { [CmdletBinding()]param([Parameter(Mandatory)]$ApplicationName, [switch]$DisableWildcardHandling) }
    function New-CMApplication {
        [CmdletBinding()]param($Name, $Publisher, $SoftwareVersion, $Description, $AutoInstall)
    }
    function New-CMDetectionClauseRegistryKeyValue {
        [CmdletBinding()]param($Hive, $KeyName, $ValueName, $PropertyType, $Value, $ExpressionOperator, $ExpectedValue)
    }
    function Add-CMScriptDeploymentType {
        [CmdletBinding()]param($ApplicationId, $DeploymentTypeName, $ContentLocation, $InstallCommand,
            $AddDetectionClause, $DetectionClauseConnector, $InstallationBehaviorType,
            $LogonRequirementType, $UserInteractionMode, $RebootBehavior,
            $EstimatedRuntimeMins, $MaximumRuntimeMins, $SlowNetworkDeploymentMode, [switch]$ContentFallback)
    }
    function Set-CMScriptDeploymentType {
        [CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)]$ApplicationName,
            $DeploymentTypeName, [switch]$DisableWildcardHandling, [bool]$ContentFallback,
            $SlowNetworkDeploymentMode, $EstimatedRuntimeMins, $MaximumRuntimeMins, $RebootBehavior)
    }
}

Describe 'Approved profiles and generated installers' {
    It 'has exactly six distinct profile names and source directories' {
        $profiles = @(Get-SpecExecProfiles)
        $profiles.Count | Should -Be 6
        @($profiles.Id | Select-Object -Unique).Count | Should -Be 6
        @($profiles.Label | Select-Object -Unique).Count | Should -Be 6
    }

    It 'matches the GUI and writes correct values for profile index <Index>' -ForEach (0..5 | ForEach-Object { @{ Index = $_ } }) {
        $profile = @(Get-SpecExecProfiles)[$Index]
        $intel = $profile.Id.StartsWith('Intel')
        $ctl = @{
            cbPriorBundle = @{ IsChecked = $intel }; cbBhi = @{ IsChecked = $intel }
            rbHtOff = @{ IsChecked = $profile.Id.StartsWith('Intel-HT-Off') }
            cbAmdBtc = @{ IsChecked = (-not $intel) }; cbAmdInception = @{ IsChecked = (-not $intel) }
            cbHyperV = @{ IsChecked = $profile.HyperV }
        }
        $state = Get-State
        $profile.Override | Should -Be $state.Override
        $profile.HyperV | Should -Be $state.NeedsMinVm
        $base = New-FakeRegistry
        $result = Invoke-FakeInstaller -Profile $profile -FakeBase $base
        $result[-1] | Should -Be 3010
        $base.Disposed | Should -BeTrue
        foreach ($s in @(Get-SpecExecSettings -Profile $profile)) {
            $base.Keys[$s.Key].Values[$s.Name] | Should -BeExactly $s.Value
            $base.Keys[$s.Key].Kinds[$s.Name] | Should -Be ([Microsoft.Win32.RegistryValueKind]$s.Kind)
            $base.Keys[$s.Key].Disposed | Should -BeTrue
        }
        $base.Keys.Count | Should -Be $(if ($profile.HyperV) { 2 } else { 1 })
    }

    It 'returns failure when registry writes fail' {
        $base = New-FakeRegistry; $base.FailWrite = $true
        $result = Invoke-FakeInstaller -Profile @(Get-SpecExecProfiles)[0] -FakeBase $base
        $result[-1] | Should -Be 1
        $base.Disposed | Should -BeTrue
    }

    It 'returns failure when registry read-back differs' {
        $base = New-FakeRegistry; $base.FailReadBack = $true
        $result = Invoke-FakeInstaller -Profile @(Get-SpecExecProfiles)[0] -FakeBase $base
        $result[-1] | Should -Be 1
        $base.Disposed | Should -BeTrue
    }

    It 'parses all generated payloads without errors or restart/uninstall commands' {
        foreach ($profile in @(Get-SpecExecProfiles)) {
            $text = New-SpecExecInstallerText -Profile $profile
            $errors = $null
            [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$errors)
            @($errors).Count | Should -Be 0
            $text | Should -Not -Match 'Restart-Computer|shutdown\.exe|Remove-ItemProperty|Get-CimInstance'
            $text | Should -Match 'RegistryView\]::Registry64'
        }
    }
}

Describe 'Content-only generation' {
    It 'generates all six scripts without connecting to MECM and can rerun unchanged' {
        Mock Connect-SpecExecSite { throw 'Must not connect' }
        $root = Join-Path $TestDrive 'content'
        $first = @(Invoke-SpecExecApplicationCreation -ContentOnly -ContentRoot $root)
        $second = @(Invoke-SpecExecApplicationCreation -ContentOnly -ContentRoot $root)
        $first.Count | Should -Be 6
        $second.Status | Should -Not -Contain 'Created'
        @(Get-ChildItem $root -Recurse -Filter Install-SpecExec.ps1).Count | Should -Be 6
        Should -Invoke Connect-SpecExecSite -Times 0
    }

    It 'writes nothing in WhatIf mode' {
        $root = Join-Path $TestDrive 'whatif'
        $result = @(Invoke-SpecExecApplicationCreation -ContentOnly -ContentRoot $root -WhatIf)
        $result.Count | Should -Be 6
        $result.Status | Should -Not -Contain 'ContentOnly'
        Test-Path -LiteralPath $root | Should -BeFalse
    }

    It 'preflights all content before writing and preserves a conflicting file' {
        $root = Join-Path $TestDrive 'conflict'
        $last = @(Get-SpecExecProfiles)[5]
        $path = Join-Path $root "SpecExec\$($last.Id)\1.0\Install-SpecExec.ps1"
        New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
        Set-Content -LiteralPath $path -Value 'user content'
        { Invoke-SpecExecApplicationCreation -ContentOnly -ContentRoot $root } | Should -Throw '*Different content*'
        @(Get-ChildItem $root -Recurse -Filter Install-SpecExec.ps1).Count | Should -Be 1
        (Get-Content -LiteralPath $path -Raw).Trim() | Should -Be 'user content'
    }

    It 'rejects relative roots and local roots for actual MECM creation' {
        { Resolve-SpecExecContentRoot -Path '..\output' -ContentOnly } | Should -Throw '*absolute*'
        { Resolve-SpecExecContentRoot -Path $TestDrive } | Should -Throw '*UNC*'
    }
}

Describe 'MECM application creation contract' {
    BeforeEach {
        $script:runRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:nextId = 100
        $script:capturedDts = @()
        Mock Resolve-SpecExecContentRoot { $script:runRoot }
        Mock Connect-SpecExecSite { }
        Mock Get-CMApplication { }
        Mock Get-CMDeploymentType { [pscustomobject]@{ LocalizedDisplayName = 'Apply registry mitigation' } }
        Mock New-CMApplication { $script:nextId++; [pscustomobject]@{ CI_ID = $script:nextId } }
        Mock Set-CMScriptDeploymentType { }
        Mock New-CMDetectionClauseRegistryKeyValue {
            [pscustomobject]@{
                Setting = [pscustomobject]@{ LogicalName = [guid]::NewGuid().ToString() }
                Name = $ValueName; Key = $KeyName; Type = $PropertyType; Expected = $ExpectedValue
            }
        }
        Mock Add-CMScriptDeploymentType {
            $script:capturedDts += @{
                Id = $ApplicationId; Content = $ContentLocation; Command = $InstallCommand
                Clauses = $AddDetectionClause; Connectors = $DetectionClauseConnector
                Reboot = $RebootBehavior; Context = $InstallationBehaviorType
                Fallback = [bool]$ContentFallback; Download = $SlowNetworkDeploymentMode
                Estimated = $EstimatedRuntimeMins; Maximum = $MaximumRuntimeMins
            }
        }
    }

    It 'creates six applications with exactly one registry-only ForceReboot DT each' {
        $result = @(Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share')
        $result.Count | Should -Be 6
        @($result | Where-Object Status -eq 'Created').Count | Should -Be 6
        Should -Invoke New-CMApplication -Times 6 -Exactly
        Should -Invoke Add-CMScriptDeploymentType -Times 6 -Exactly
        Should -Invoke Get-CMDeploymentType -Times 6 -Exactly
        Should -Invoke Get-CMDeploymentType -Times 6 -Exactly -ParameterFilter {
            $ApplicationName -like 'Speculative Execution Mitigations -*' -and $DisableWildcardHandling
        }
        Should -Invoke Set-CMScriptDeploymentType -Times 6 -Exactly -ParameterFilter {
            $ContentFallback -and $SlowNetworkDeploymentMode -eq 'Download' -and
            $EstimatedRuntimeMins -eq 15 -and $MaximumRuntimeMins -eq 20 -and
            $RebootBehavior -eq 'ForceReboot' -and $DeploymentTypeName -eq 'Apply registry mitigation'
        }
        Should -Invoke New-CMDetectionClauseRegistryKeyValue -Times 15 -Exactly -ParameterFilter {
            $Hive -eq 'LocalMachine' -and $ExpressionOperator -eq 'IsEquals' -and $Value
        }
        @($script:capturedDts.Id | Select-Object -Unique).Count | Should -Be 6
        for ($i = 0; $i -lt 6; $i++) {
            $dt = $script:capturedDts[$i]
            $dt.Reboot | Should -Be 'ForceReboot'
            $dt.Context | Should -Be 'InstallForSystem'
            $dt.Fallback | Should -BeTrue
            $dt.Download | Should -Be 'Download'
            $dt.Estimated | Should -Be 15
            $dt.Maximum | Should -Be 20
            $dt.Command | Should -Be 'PowerShell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "Install-SpecExec.ps1"'
            $dt.Clauses.Count | Should -Be $(if ($i -ge 3) { 3 } else { 2 })
            @($dt.Connectors).Count | Should -Be ($dt.Clauses.Count - 1)
            foreach ($connector in $dt.Connectors) {
                $connector.Connector | Should -Be 'And'
                $dt.Clauses.Setting.LogicalName | Should -Contain $connector.LogicalName
            }
            $dt.Clauses[0].Type | Should -Be 'Integer'
            $dt.Clauses[0].Expected | Should -Be ([string]@(Get-SpecExecProfiles)[$i].Override)
            $dt.Clauses[1].Expected | Should -Be '3'
            if ($i -ge 3) { $dt.Clauses[2].Type | Should -Be 'String'; $dt.Clauses[2].Expected | Should -Be '1.0' }
        }
    }

    It 'creates neither content nor applications for creation WhatIf' {
        [void](Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' -WhatIf)
        Should -Invoke New-CMApplication -Times 0
        Should -Invoke Add-CMScriptDeploymentType -Times 0
        Should -Invoke Set-CMScriptDeploymentType -Times 0
        Test-Path $script:runRoot | Should -BeFalse
    }

    It 'fails before writes when any app already exists' {
        Mock Get-CMApplication { [pscustomobject]@{ CI_ID = 40 } } -ParameterFilter { $Name -like '*AMD - Hyper-V Host' }
        { Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' } | Should -Throw '*already exists*'
        Should -Invoke New-CMApplication -Times 0
        Test-Path $script:runRoot | Should -BeFalse
    }

    It 'skips existing apps without rewriting their content' {
        Mock Get-CMApplication { [pscustomobject]@{ CI_ID = 40 } }
        $result = @(Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' -OnExisting Skip)
        @($result | Where-Object Status -eq 'Skipped').Count | Should -Be 6
        Should -Invoke New-CMApplication -Times 0
        Test-Path $script:runRoot | Should -BeFalse
    }

    It 'rejects an incomplete existing application instead of silently skipping it' {
        Mock Get-CMApplication { [pscustomobject]@{ CI_ID = 40 } }
        Mock Get-CMDeploymentType { }
        { Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' -OnExisting Skip } | Should -Throw '*0 DTs*'
        Should -Invoke New-CMApplication -Times 0
    }

    It 'reports partial creation failures with the application name and stops' {
        Mock Add-CMScriptDeploymentType { throw 'Provider failure' }
        { Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' } | Should -Throw '*CI_ID 101*Provider failure*'
        Should -Invoke New-CMApplication -Times 1 -Exactly
    }

    It 'does not hide duplicate-query errors as a missing application' {
        Mock Get-CMApplication { throw 'Provider unreachable' }
        { Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' } | Should -Throw '*Provider unreachable*'
        Should -Invoke New-CMApplication -Times 0
        Test-Path $script:runRoot | Should -BeFalse
    }

    It 'repairs the first app in place and creates the other five on rerun' {
        Mock Get-CMApplication { [pscustomobject]@{ CI_ID = 40 } } -ParameterFilter { $Name -eq 'Speculative Execution Mitigations - Intel - HT Enabled - Standard' }
        $result = @(Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' -OnExisting Repair)
        @($result | Where-Object Status -eq 'Repaired').Count | Should -Be 1
        @($result | Where-Object Status -eq 'Created').Count | Should -Be 5
        Should -Invoke New-CMApplication -Times 5 -Exactly
        Should -Invoke Add-CMScriptDeploymentType -Times 5 -Exactly
        Should -Invoke Set-CMScriptDeploymentType -Times 6 -Exactly
        Should -Invoke Set-CMScriptDeploymentType -Times 1 -Exactly -ParameterFilter {
            $ApplicationName -eq 'Speculative Execution Mitigations - Intel - HT Enabled - Standard' -and
            $ContentFallback -and $SlowNetworkDeploymentMode -eq 'Download' -and
            $EstimatedRuntimeMins -eq 15 -and $MaximumRuntimeMins -eq 20
        }
        Test-Path (Join-Path $script:runRoot 'SpecExec\Intel-HT-On-Standard') | Should -BeFalse
    }

    It 'does not mutate existing applications or files for repair WhatIf' {
        Mock Get-CMApplication { [pscustomobject]@{ CI_ID = 40 } }
        $result = @(Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' -OnExisting Repair -WhatIf)
        @($result | Where-Object Status -eq 'WhatIf').Count | Should -Be 6
        Should -Invoke Set-CMScriptDeploymentType -Times 0
        Should -Invoke New-CMApplication -Times 0
        Test-Path $script:runRoot | Should -BeFalse
    }

    It 'refuses to repair an unexpected deployment type' {
        Mock Get-CMApplication { [pscustomobject]@{ CI_ID = 40 } }
        Mock Get-CMDeploymentType { [pscustomobject]@{ LocalizedDisplayName = 'User-authored DT' } }
        { Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' -OnExisting Repair } | Should -Throw '*unexpected DT name*'
        Should -Invoke Set-CMScriptDeploymentType -Times 0
    }

    It 'distinguishes a post-creation verification failure from DT creation failure' {
        Mock Get-CMDeploymentType { throw 'Verification read failed' }
        { Invoke-SpecExecApplicationCreation -SiteCode MCM -SiteServer cm01 -ContentRoot '\\server\share' } | Should -Throw '*DT verification failed*Verification read failed*'
        Should -Invoke Add-CMScriptDeploymentType -Times 1 -Exactly
    }
}
