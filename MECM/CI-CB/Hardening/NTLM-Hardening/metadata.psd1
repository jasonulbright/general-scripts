@{
    # === Identity ===
    Id          = 'ntlm-lmcompatibilitylevel'
    Version     = '1.0.0'
    DisplayName = 'NTLM LmCompatibilityLevel'
    Subcategory = 'Hardening'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Enforces NTLMv2-only authentication (LmCompatibilityLevel = 5; refuse LM & NTLMv1). Mitigates crackable/relayable legacy auth. Missed because nothing visibly breaks when weak protocols stay allowed. Single DWORD; no reboot. Test legacy appliances first.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows/security/threat-protection/security-policy-settings/network-security-lan-manager-authentication-level')

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
            KeyPath = 'SYSTEM\CurrentControlSet\Control\Lsa'
            Values  = @('LmCompatibilityLevel')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-NTLMHardeningBaseline.ps1'
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
        ConfigurationItems     = @('Hardening: NTLM LmCompatibilityLevel')
        ConfigurationBaselines = @('Hardening NTLM LmCompatibilityLevel')
    }
}
