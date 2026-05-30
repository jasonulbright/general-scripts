@{
    # === Identity ===
    Id          = 'tls-legacy-disable'
    Version     = '1.0.0'
    DisplayName = 'TLS Legacy Disable (SCHANNEL + .NET 4.x)'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Disables SSL 2.0, SSL 3.0, TLS 1.0, TLS 1.1 (server + client) in SCHANNEL, explicitly enables TLS 1.2 (server + client), and forces .NET Framework 4.x to system-default strong crypto in both 64-bit and WOW6432Node paths. 24 native DWORD settings on one CI. Reboot required for SCHANNEL reload.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @(20007, 104743, 157288)
    KbReferences   = @()

    # === Scope ===
    OsScope = @{
        Client = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows 11')
        Server = @('Server 2008 R2', 'Server 2012', 'Server 2012 R2', 'Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $true

    # === Reg surface ===
    RegistrySurface = @(
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client'; Values = @('Enabled', 'DisabledByDefault') }
        @{ Hive = 'HKLM'; KeyPath = 'SOFTWARE\Microsoft\.NETFramework\v4.0.30319';            Values = @('SchUseStrongCrypto', 'SystemDefaultTlsVersions') }
        @{ Hive = 'HKLM'; KeyPath = 'SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319'; Values = @('SchUseStrongCrypto', 'SystemDefaultTlsVersions') }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-TLSLegacyDisableBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';       Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SiteServer';     Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site server FQDN.' }
            @{ Name = 'CollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'If specified, deploys the baseline to this collection daily.' }
            @{ Name = 'DetectOnly';     Type = 'Switch'; Required = $false; Default = $false; Description = 'Create with remediation disabled.' }
        )
    }

    # === Dependencies ===
    DependsOn = @()

    # === MECM artifacts produced ===
    Produces = @{
        ConfigurationItems     = @('Compliance: TLS Legacy Disable')
        ConfigurationBaselines = @('Compliance TLS Legacy Disable')
    }
}
