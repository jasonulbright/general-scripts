#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for the zero-touch factory reset project.
    Tests configuration, templates, and script structure WITHOUT
    triggering any reset or modifying the system.
#>

BeforeAll {
    $script:projectRoot = $PSScriptRoot
    $script:configPath = Join-Path $projectRoot 'Reset-Config.json'
    $script:templatePath = Join-Path $projectRoot 'unattend-template.xml'
    $script:prepScriptPath = Join-Path $projectRoot 'Invoke-PrepareReset.ps1'
    $script:resetScriptPath = Join-Path $projectRoot 'Invoke-FactoryReset.ps1'
    $script:postSetupPath = Join-Path $projectRoot 'post-setup.ps1'
}

# ============================================================================
# Script parsing
# ============================================================================

Describe 'Script files parse without errors' {

    It 'Invoke-PrepareReset.ps1 parses cleanly' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($prepScriptPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'Invoke-FactoryReset.ps1 parses cleanly' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($resetScriptPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'post-setup.ps1 parses cleanly' {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($postSetupPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }
}

# ============================================================================
# Reset-Config.json
# ============================================================================

Describe 'Reset-Config.json' {

    It 'Exists and is valid JSON' {
        Test-Path $configPath | Should -BeTrue
        { Get-Content $configPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    BeforeAll {
        $script:config = Get-Content $configPath -Raw | ConvertFrom-Json
    }

    It 'Has Domain section with FQDN, NetBIOS, DefaultOU' {
        $config.Domain | Should -Not -BeNullOrEmpty
        $config.Domain.FQDN | Should -Not -BeNullOrEmpty
        $config.Domain.NetBIOS | Should -Not -BeNullOrEmpty
        $config.Domain.DefaultOU | Should -Not -BeNullOrEmpty
    }

    It 'Domain FQDN contains a dot' {
        $config.Domain.FQDN | Should -Match '\.'
    }

    It 'DefaultOU is a valid DN format' {
        $config.Domain.DefaultOU | Should -Match '^OU=.*,DC=.*'
    }

    It 'Has Apps section' {
        $config.Apps | Should -Not -BeNullOrEmpty
    }

    It 'Each app has InstallerPath and SilentArgs' {
        foreach ($prop in $config.Apps.PSObject.Properties) {
            $prop.Value.InstallerPath | Should -Not -BeNullOrEmpty -Because "$($prop.Name) needs InstallerPath"
            $prop.Value.SilentArgs | Should -Not -BeNullOrEmpty -Because "$($prop.Name) needs SilentArgs"
        }
    }

    It 'Has Recovery paths' {
        $config.Recovery.CustomizationsPath | Should -Not -BeNullOrEmpty
        $config.Recovery.AutoApplyPath | Should -Not -BeNullOrEmpty
    }
}

# ============================================================================
# unattend-template.xml
# ============================================================================

Describe 'unattend-template.xml' {

    It 'Exists' {
        Test-Path $templatePath | Should -BeTrue
    }

    It 'Is well-formed XML' {
        { [xml](Get-Content $templatePath -Raw) } | Should -Not -Throw
    }

    BeforeAll {
        $script:templateContent = Get-Content $templatePath -Raw
    }

    It 'Contains COMPUTERNAME placeholder' {
        $templateContent | Should -Match '{{COMPUTERNAME}}'
    }

    It 'Contains LOCALE placeholder' {
        $templateContent | Should -Match '{{LOCALE}}'
    }

    It 'Contains KEYBOARD placeholder' {
        $templateContent | Should -Match '{{KEYBOARD}}'
    }

    It 'References post-setup.ps1 in FirstLogonCommands' {
        $templateContent | Should -Match 'post-setup\.ps1'
    }

    It 'Includes BypassNRO for 24H2 compatibility' {
        $templateContent | Should -Match 'BypassNRO'
    }

    It 'Skips OOBE screens' {
        $templateContent | Should -Match 'SkipUserOOBE.*true'
        $templateContent | Should -Match 'SkipMachineOOBE.*true'
        $templateContent | Should -Match 'HideEULAPage.*true'
    }

    It 'Creates SetupComplete.cmd in specialize pass' {
        $templateContent | Should -Match 'SetupComplete\.cmd'
    }

    It 'Does not use temp admin or auto-logon' {
        $templateContent | Should -Not -Match 'AutoLogon'
        $templateContent | Should -Not -Match 'TEMP_ADMIN'
    }

    It 'Is valid XML after placeholder substitution' {
        $filled = $templateContent
        $filled = $filled -replace '{{COMPUTERNAME}}', 'TESTPC01'
        $filled = $filled -replace '{{LOCALE}}', 'en-US'
        $filled = $filled -replace '{{KEYBOARD}}', '0409:00000409'
        { [xml]$filled } | Should -Not -Throw
    }

    It 'Has no remaining placeholders after substitution' {
        $filled = $templateContent
        $filled = $filled -replace '{{COMPUTERNAME}}', 'TESTPC01'
        $filled = $filled -replace '{{LOCALE}}', 'en-US'
        $filled = $filled -replace '{{KEYBOARD}}', '0409:00000409'
        $filled | Should -Not -Match '{{.*}}'
    }
}

# ============================================================================
# System prerequisites
# ============================================================================

Describe 'System prerequisites' {

    It 'djoin.exe exists' {
        Test-Path (Join-Path $env:SystemRoot 'System32\djoin.exe') | Should -BeTrue
    }

    It 'MDM_RemoteWipe CIM class exists' {
        $instance = Get-CimInstance -Namespace 'root\cimv2\mdm\dmmap' -ClassName 'MDM_RemoteWipe' -ErrorAction SilentlyContinue
        $instance | Should -Not -BeNullOrEmpty
    }

    It 'C:\Recovery\ is writable' {
        $testFile = 'C:\Recovery\__pester_write_test__'
        New-Item -Path 'C:\Recovery' -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
        { Set-Content -Path $testFile -Value 'test' -ErrorAction Stop } | Should -Not -Throw
        Remove-Item $testFile -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Script structure
# ============================================================================

Describe 'Invoke-PrepareReset.ps1 structure' {

    BeforeAll {
        $script:prepContent = Get-Content $prepScriptPath -Raw
    }

    It 'Requires administrator' {
        $prepContent | Should -Match '#Requires -RunAsAdministrator'
    }

    It 'Has -ConfigPath parameter' {
        $prepContent | Should -Match '\$ConfigPath'
    }

    It 'Has -Force parameter' {
        $prepContent | Should -Match '\[switch\]\$Force'
    }

    It 'Has -SkipReset parameter' {
        $prepContent | Should -Match '\[switch\]\$SkipReset'
    }

    It 'Supports -WhatIf' {
        $prepContent | Should -Match 'SupportsShouldProcess'
    }

    It 'Calls djoin.exe with /provision and /reuse' {
        $prepContent | Should -Match 'djoin\.exe'
        $prepContent | Should -Match '/provision'
        $prepContent | Should -Match '/reuse'
    }

    It 'Replaces COMPUTERNAME placeholder' {
        $prepContent | Should -Match "COMPUTERNAME"
    }

    It 'Does not create temp admin accounts' {
        $prepContent | Should -Not -Match 'TEMP_ADMIN'
    }

    It 'Validates staging before reset' {
        $prepContent | Should -Match 'Validating staged artifacts'
    }

    It 'Aborts if staging incomplete' {
        $prepContent | Should -Match 'Staging incomplete.*Aborting'
    }
}

Describe 'post-setup.ps1 structure' {

    BeforeAll {
        $script:postContent = Get-Content $postSetupPath -Raw
    }

    It 'Has idempotent guard via registry' {
        $postContent | Should -Match 'SetupComplete'
    }

    It 'Applies offline domain join via djoin /requestODJ' {
        $postContent | Should -Match 'djoin\.exe'
        $postContent | Should -Match '/requestODJ'
    }

    It 'Cleans up SetupComplete.cmd after running' {
        $postContent | Should -Match 'SetupComplete\.cmd'
        $postContent | Should -Match 'Remove-Item'
    }

    It 'Does not reference temp admin or auto-logon' {
        $postContent | Should -Not -Match 'AutoAdminLogon'
        $postContent | Should -Not -Match 'Remove-LocalUser'
    }

    It 'Reboots at the end' {
        $postContent | Should -Match 'Restart-Computer'
    }

    It 'Logs to post-setup.log' {
        $postContent | Should -Match 'Start-Transcript'
        $postContent | Should -Match 'post-setup\.log'
    }
}

Describe 'Invoke-FactoryReset.ps1 pre-flight check' {

    BeforeAll {
        $script:resetContent = Get-Content $resetScriptPath -Raw
    }

    It 'Checks for recovery payload before wiping' {
        $resetContent | Should -Match 'post-setup\.ps1'
        $resetContent | Should -Match 'unattend\.xml'
        $resetContent | Should -Match 'recovery payload'
    }
}
