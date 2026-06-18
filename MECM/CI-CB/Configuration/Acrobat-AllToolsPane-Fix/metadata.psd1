@{
    # === Identity ===
    Id          = 'acrobat-alltoolspane-fix'
    Version     = '1.0.0'
    DisplayName = 'Acrobat All Tools Pane Fix'
    Subcategory = 'Configuration'
    Mechanism   = 'NativeRegistry'
    Status      = 'Draft'

    # === Summary ===
    Description = 'Temporary Adobe-supplied workaround for the Acrobat bug where the All Tools pane disappears / goes empty on Edit PDF (bGenCoverPagesLabelStrings = 1 under FeatureLockDown). Restart Acrobat + host to apply. RETIRE once Adobe ships the permanent patch.'
    Severity    = 'Warning'

    # === References ===
    Cves           = @()
    TenablePlugins = @()
    KbReferences   = @('https://community.adobe.com/questions-9/all-tools-pane-disappears-empty-when-i-select-edit-pdf-1628319')

    # === Scope ===
    OsScope = @{
        Client = @('Windows 10', 'Windows 11')
        Server = @('Server 2016', 'Server 2019', 'Server 2022', 'Server 2025')
    }
    RebootRequired = $true

    # === Reg surface ===
    RegistrySurface = @(
        @{
            Hive    = 'HKLM'
            KeyPath = 'SOFTWARE\Policies\Adobe\Adobe Acrobat\DC\FeatureLockDown'
            Values  = @('bGenCoverPagesLabelStrings')
        }
    )

    # === Builder ===
    Builder = @{
        ScriptPath = 'New-AcrobatAllToolsPaneFixBaseline.ps1'
        Parameters = @(
            @{ Name = 'SiteCode';       Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site code.' }
            @{ Name = 'SiteServer';     Type = 'String'; Required = $true;  Default = $null;  Description = 'MECM site server FQDN.' }
            @{ Name = 'CollectionName'; Type = 'String'; Required = $false; Default = $null;  Description = 'If specified, deploys the baseline to this collection daily. Target machines with Acrobat installed.' }
            @{ Name = 'DetectOnly';     Type = 'Switch'; Required = $false; Default = $false; Description = 'Create / deploy without remediation.' }
        )
    }

    # === Dependencies ===
    # Temporary vendor-bug workaround. Retire when Adobe's permanent patch is deployed.
    DependsOn = @()

    # === MECM artifacts produced ===
    Produces = @{
        ConfigurationItems     = @('Configuration: Acrobat All Tools Pane Fix')
        ConfigurationBaselines = @('Configuration Acrobat All Tools Pane Fix')
    }
}
