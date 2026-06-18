@{
    # === Identity ===
    Id          = 'autorun-autoplay-disable'
    Version     = '1.0.0'
    DisplayName = 'Autorun/Autoplay Disable'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Disables Autorun/Autoplay on all drive types (NoDriveTypeAutoRun = 255). Defeats malicious removable-media / mapped-share autorun infection. Long-standing CIS/STIG item dropped because Autoplay feels like UX, not attack surface. Single DWORD; no reboot.'
    Severity    = 'Warning'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/security-options')

    # === Scope ===
    OsScope = @{
        Client = @('Windows 7', 'Windows 8.1', 'Windows 10', 'Windows 11')
        Server = @('Server 2008 R2', 'Server 2012', 'Server 2012 R2', 'Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $false

    # === Reg surface ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
            Values  = @('NoDriveTypeAutoRun')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-AutorunDisableBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';       Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SiteServer';     Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site server FQDN.' }
            @{ Name = 'CollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'If specified, deploys the baseline to this collection daily.' }
            @{ Name = 'DetectOnly';     Type = 'Switch'; Required = $false; Default = $false; Description = 'Create / deploy without remediation.' }
        )
    }

    # === Dependencies ===
    DependsOn = @()

    # === MECM artifacts produced ===
    Produces = @{
        ConfigurationItems     = @('Compliance: Autorun/Autoplay Disable')
        ConfigurationBaselines = @('Compliance Autorun Autoplay Disable')
    }
}
