@{
    # === Identity ===
    Id          = 'installer-alwaysinstallelevated-disable'
    Version     = '1.0.0'
    DisplayName = 'Windows Installer AlwaysInstallElevated Disable'
    Subcategory = 'Compliance'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Disables Windows Installer AlwaysInstallElevated (HKLM = 0). Removes a textbook local privilege-escalation primitive (malicious MSI -> SYSTEM). Buried in a rarely visited Installer policy node, so commonly missed. Single DWORD; no reboot. HKCU copy is per-user; HKLM=0 alone neutralizes elevation.'
    Severity    = 'Critical'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://learn.microsoft.com/windows/win32/msi/alwaysinstallelevated')

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
            KeyPath = 'SOFTWARE\Policies\Microsoft\Windows\Installer'
            Values  = @('AlwaysInstallElevated')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-NoElevatedInstallBaseline.ps1'
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
        ConfigurationItems     = @('Compliance: Windows Installer AlwaysInstallElevated Disable')
        ConfigurationBaselines = @('Compliance Installer AlwaysInstallElevated Disable')
    }
}
