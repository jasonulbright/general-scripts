#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    Import-Module -Name Microsoft.PowerShell.Security

    $script:toolPath = Join-Path $PSScriptRoot 'Sign-ExcelMacros.ps1'
    $script:toolText = [System.IO.File]::ReadAllText($script:toolPath)

    # Only definitions sit above the startup region; the startup region builds and shows the window.
    $startupIndex = $script:toolText.IndexOf('#region Startup')
    $definitions = ($script:toolText.Substring(0, $startupIndex) -split "`r?`n" | Where-Object { $_ -notmatch '^#Requires' }) -join "`n"
    . ([scriptblock]::Create($definitions))

    # A modal message box would block the run; messages are recorded instead.
    $script:shownMessages = [System.Collections.Generic.List[string]]::new()
    function Show-Message {
        $script:shownMessages.Add(($args -join ' '))
    }

    function Build-TestCertificate {
        param([bool]$CodeSigning)

        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=Sign-ExcelMacros Test', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        if ($CodeSigning) {
            $oids = [System.Security.Cryptography.OidCollection]::new()
            [void]$oids.Add([System.Security.Cryptography.Oid]::new('1.3.6.1.5.5.7.3.3'))
            $request.CertificateExtensions.Add([System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]::new($oids, $false))
        }
        $request.CreateSelfSigned([DateTimeOffset]::Now.AddMinutes(-5), [DateTimeOffset]::Now.AddDays(1))
    }

    function Build-TestPfx {
        param(
            [string]$Path,
            [bool]$CodeSigning,
            [string]$Protection
        )

        $certificate = Build-TestCertificate -CodeSigning $CodeSigning
        try {
            [System.IO.File]::WriteAllBytes($Path, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Protection))
        }
        finally {
            $certificate.Dispose()
        }
    }

    function ConvertTo-TestSecureString {
        param([string]$Value)

        $secure = [System.Security.SecureString]::new()
        foreach ($character in $Value.ToCharArray()) {
            $secure.AppendChar($character)
        }
        $secure.MakeReadOnly()
        $secure
    }

    function Clear-TestKey {
        param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

        $key = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
        if ($key -is [System.Security.Cryptography.RSACng]) {
            $key.Key.Delete()
        }
        elseif ($key -is [System.Security.Cryptography.RSACryptoServiceProvider]) {
            $key.PersistKeyInCsp = $false
            $key.Clear()
        }
        $Certificate.Dispose()
    }

    function Build-TestZip {
        param(
            [string]$Path,
            [string[]]$Entries
        )

        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($name in $Entries) {
                $writer = [System.IO.StreamWriter]::new($zip.CreateEntry($name).Open())
                try {
                    $writer.Write('x')
                }
                finally {
                    $writer.Dispose()
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }

    function Wait-BackgroundJob {
        param([int]$TimeoutSeconds = 120)

        $frame = [System.Windows.Threading.DispatcherFrame]::new()
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        $poll = [System.Windows.Threading.DispatcherTimer]::new()
        $poll.Interval = [TimeSpan]::FromMilliseconds(100)
        $poll.Add_Tick({
            if ($null -eq $script:Job -or [DateTime]::UtcNow -gt $deadline) {
                $poll.Stop()
                $frame.Continue = $false
            }
        })
        $poll.Start()
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
        $null -eq $script:Job
    }

    function Build-TestMainWindow {
        $script:MainWindow = [System.Windows.Markup.XamlReader]::Parse($script:MainXaml)
        $script:ui = @{}
        foreach ($match in [regex]::Matches($script:MainXaml, 'x:Name="(\w+)"')) {
            $script:ui[$match.Groups[1].Value] = $script:MainWindow.FindName($match.Groups[1].Value)
        }
        $script:ui.FileGrid.ItemsSource = $script:Rows
        $script:Rows.Clear()
        $script:RowIndex.Clear()
        $script:shownMessages.Clear()
        Use-SigningCertificate -Certificate $null
    }
}

Describe 'Sign-ExcelMacros.ps1 source' {

    It 'parses without errors' {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($script:toolPath, [ref]$null, [ref]$errors)
        $errors.Count | Should -Be 0
    }

    It 'contains only ASCII characters' {
        $script:toolText | Should -Not -Match '[^\x00-\x7F]'
    }

    It 'does not rebind scriptblocks with GetNewClosure' {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($script:toolText, [ref]$null, [ref]$null)
        $closures = $ast.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $node.Member.Extent.Text -eq 'GetNewClosure'
        }, $true)
        @($closures).Count | Should -Be 0
    }

    It 'loads the password and certificate picker XAML' {
        { [void][System.Windows.Markup.XamlReader]::Parse($script:PasswordXaml) } | Should -Not -Throw
        { [void][System.Windows.Markup.XamlReader]::Parse($script:PickerXaml) } | Should -Not -Throw
    }

    It 'resolves every main-window control the startup code looks up' {
        $window = [System.Windows.Markup.XamlReader]::Parse($script:MainXaml)
        $startupText = $script:toolText.Substring($script:toolText.IndexOf('#region Startup'))
        $lookup = [regex]::Match($startupText, 'foreach \(\$name in (?<names>[^)]+)\)').Groups['names'].Value
        $names = @([regex]::Matches($lookup, "'(\w+)'") | ForEach-Object { $_.Groups[1].Value })
        $names.Count | Should -BeGreaterThan 10
        foreach ($name in $names) {
            $window.FindName($name) | Should -Not -BeNullOrEmpty -Because "startup looks up $name"
        }
    }
}

Describe 'Certificate handling' {

    It 'accepts only certificates with the Code Signing EKU' {
        $withEku = Build-TestCertificate -CodeSigning $true
        $withoutEku = Build-TestCertificate -CodeSigning $false
        try {
            Test-CodeSigningUsage -Certificate $withEku | Should -BeTrue
            Test-CodeSigningUsage -Certificate $withoutEku | Should -BeFalse
        }
        finally {
            $withEku.Dispose()
            $withoutEku.Dispose()
        }
    }

    It 'labels a certificate with simple names and an ISO expiry date' {
        $certificate = Build-TestCertificate -CodeSigning $true
        try {
            $label = Get-CertificateLabel -Certificate $certificate
            $label.IssuedTo | Should -Be 'Sign-ExcelMacros Test'
            $label.IssuedBy | Should -Be 'Sign-ExcelMacros Test'
            $label.Expires | Should -Match '^\d{4}-\d{2}-\d{2}$'
            $label.Thumbprint | Should -Be $certificate.Thumbprint
        }
        finally {
            $certificate.Dispose()
        }
    }

    It 'offers only currently valid code-signing certificates that have a private key' {
        $now = Get-Date
        foreach ($certificate in @(Get-SigningCertificate)) {
            $certificate.HasPrivateKey | Should -BeTrue
            $certificate.NotBefore | Should -BeLessOrEqual $now
            $certificate.NotAfter | Should -BeGreaterThan $now
            Test-CodeSigningUsage -Certificate $certificate | Should -BeTrue
        }
    }

    It 'rejects a PFX without the Code Signing EKU and leaves the personal store unchanged' {
        $before = @(Get-ChildItem -Path Cert:\CurrentUser\My).Count
        $pfxPath = Join-Path $TestDrive 'no-eku.pfx'
        Build-TestPfx -Path $pfxPath -CodeSigning $false -Protection 'test-protection'

        { Import-PfxToUserStore -Path $pfxPath -Password (ConvertTo-TestSecureString -Value 'test-protection') } |
            Should -Throw -ExpectedMessage '*not valid for code signing*'
        @(Get-ChildItem -Path Cert:\CurrentUser\My).Count | Should -Be $before
    }

    It 'rejects a wrong PFX password and leaves the personal store unchanged' {
        $before = @(Get-ChildItem -Path Cert:\CurrentUser\My).Count
        $pfxPath = Join-Path $TestDrive 'code-signing.pfx'
        Build-TestPfx -Path $pfxPath -CodeSigning $true -Protection 'test-protection'

        $thrown = $null
        try {
            [void](Import-PfxToUserStore -Path $pfxPath -Password (ConvertTo-TestSecureString -Value 'wrong'))
        }
        catch {
            $thrown = $_.Exception
        }
        $thrown | Should -Not -BeNullOrEmpty
        ($thrown -is [System.Security.Cryptography.CryptographicException] -or
            $thrown.InnerException -is [System.Security.Cryptography.CryptographicException]) | Should -BeTrue
        @(Get-ChildItem -Path Cert:\CurrentUser\My).Count | Should -Be $before
    }
}

Describe 'Office SIP detection' {

    It 'reports one registration row per registry view' {
        $rows = @(Get-OfficeSipRegistration)
        $expected = if ([Environment]::Is64BitOperatingSystem) { 2 } else { 1 }
        $rows.Count | Should -Be $expected
        foreach ($row in $rows) {
            $row.OpenXml | Should -BeOfType [bool]
            $row.Legacy | Should -BeOfType [bool]
        }
    }

    It 'flags a missing SIP only where one is required: <Path>' -ForEach @(
        @{ Path = 'C:\x\Report.xlsm'; Missing = $true }
        @{ Path = 'C:\x\Report.xls'; Missing = $false }
        @{ Path = 'C:\x\Script.ps1'; Missing = $false }
    ) {
        $script:SipCurrent = [pscustomobject]@{ Is64Bit = $true; OpenXml = $false; Legacy = $true }
        $gap = Get-SipGap -Path $Path
        if ($Missing) {
            $gap | Should -BeLike 'Not signed: the Office SIP for .xlsm files is not registered*'
        }
        else {
            $gap | Should -BeNullOrEmpty
        }
    }
}

Describe 'Folder scan' {

    BeforeAll {
        $scanRoot = Join-Path $TestDrive 'scan'
        $docs = [System.IO.Directory]::CreateDirectory((Join-Path $scanRoot 'docs')).FullName
        $sub = [System.IO.Directory]::CreateDirectory((Join-Path $docs 'sub')).FullName
        $brackets = [System.IO.Directory]::CreateDirectory((Join-Path $scanRoot '[brackets]')).FullName

        Build-TestZip -Path (Join-Path $docs 'WithMacros.xlsm') -Entries '[Content_Types].xml', 'xl/workbook.xml', 'xl/vbaProject.bin'
        Build-TestZip -Path (Join-Path $docs 'NoMacros.xlsm') -Entries '[Content_Types].xml', 'xl/workbook.xml'
        Build-TestZip -Path (Join-Path $sub 'Addin.xlam') -Entries 'xl/vbaProject.bin'
        Build-TestZip -Path (Join-Path $brackets 'Budget [2024].xlsb') -Entries 'xl/vbaProject.bin'

        $legacy = [byte[]]::new(2048)
        $marker = [System.Text.Encoding]::Unicode.GetBytes('_VBA_PROJECT_CUR')
        [Array]::Copy($marker, 0, $legacy, 1024, $marker.Length)
        [System.IO.File]::WriteAllBytes((Join-Path $docs 'Legacy.xls'), $legacy)
        [System.IO.File]::WriteAllBytes((Join-Path $docs 'LegacyNoMacros.xls'), [byte[]]::new(2048))
        [System.IO.File]::WriteAllText((Join-Path $sub '~$WithMacros.xlsm'), 'owner file')
        [System.IO.File]::WriteAllText((Join-Path $docs 'notes.txt'), 'not excel')
        [System.IO.File]::WriteAllText((Join-Path $docs 'Corrupt.xlsm'), 'not a zip archive')

        $script:scanned = @{}
        $script:scanDone = $null
        $script:scanFailure = $null
        Invoke-BackgroundJob -Worker $script:ScanWorker -Parameters @{
            Paths             = [string[]]@($docs, (Join-Path $brackets 'Budget [2024].xlsb'))
            OpenXmlExtensions = [string[]]$script:OpenXmlExtensions
            LegacyExtensions  = [string[]]$script:LegacyExtensions
        } -OnMessage {
            param($Message)
            if ($Message.Kind -eq 'File') {
                $script:scanned[[System.IO.Path]::GetFileName($Message.Path)] = $Message
            }
            else {
                $script:scanDone = $Message
            }
        } -OnComplete {
            param($Failure)
            $script:scanFailure = $Failure
        }
        $script:scanCompleted = Wait-BackgroundJob
    }

    It 'completes and reports no unreadable folders' {
        $script:scanCompleted | Should -BeTrue
        $script:scanFailure | Should -BeNullOrEmpty
        $script:scanDone.UnreadableFolders | Should -Be 0
    }

    It 'classifies <Name> as <Status>' -ForEach @(
        @{ Name = 'WithMacros.xlsm'; Status = 'Ready' }
        @{ Name = 'NoMacros.xlsm'; Status = 'Skipped' }
        @{ Name = 'Corrupt.xlsm'; Status = 'Skipped' }
        @{ Name = 'Legacy.xls'; Status = 'Ready' }
        @{ Name = 'LegacyNoMacros.xls'; Status = 'Skipped' }
        @{ Name = 'Addin.xlam'; Status = 'Ready' }
        @{ Name = 'Budget [2024].xlsb'; Status = 'Ready' }
    ) {
        $script:scanned[$Name].Status | Should -Be $Status
    }

    It 'ignores Office owner files and non-Excel files' {
        $script:scanned.Keys | Should -Not -Contain '~$WithMacros.xlsm'
        $script:scanned.Keys | Should -Not -Contain 'notes.txt'
        $script:scanned.Count | Should -Be 7
    }
}

Describe 'File list and Sign button' {

    BeforeAll {
        $listRoot = [System.IO.Directory]::CreateDirectory((Join-Path $TestDrive 'list')).FullName
        Build-TestZip -Path (Join-Path $listRoot 'One.xlsm') -Entries 'xl/vbaProject.bin'
        Build-TestZip -Path (Join-Path $listRoot 'Two.xlsm') -Entries 'xl/workbook.xml'

        Build-TestMainWindow
        Add-InputPath -Path @($listRoot, (Join-Path $listRoot 'One.xlsm'))
        $script:listCompleted = Wait-BackgroundJob
    }

    It 'lists each file once, even when dropped twice' {
        $script:listCompleted | Should -BeTrue
        $script:Rows.Count | Should -Be 2
        $script:shownMessages.Count | Should -Be 0
    }

    It 'counts ready files and stays disabled without a certificate' {
        $script:ui.SignButton.Content | Should -Be 'Sign 1 file'
        $script:ui.SignButton.IsEnabled | Should -BeFalse
        $script:ui.AddFilesButton.IsEnabled | Should -BeTrue
    }

    It 'enables signing once a certificate is selected' {
        $certificate = Build-TestCertificate -CodeSigning $true
        try {
            Use-SigningCertificate -Certificate $certificate
            $script:ui.SignButton.IsEnabled | Should -BeTrue
            $script:ui.CertText.Text | Should -Be 'Sign-ExcelMacros Test'
        }
        finally {
            Use-SigningCertificate -Certificate $null
            $certificate.Dispose()
        }
    }
}

Describe 'Signing' {

    BeforeAll {
        function Get-OfficeSipRegistration {
            [pscustomobject]@{ Is64Bit = [Environment]::Is64BitProcess; OpenXml = $false; Legacy = $false }
        }

        Build-TestMainWindow
        $signRoot = [System.IO.Directory]::CreateDirectory((Join-Path $TestDrive 'sign [x]')).FullName
        $script:scriptFile = Join-Path $signRoot 'Sample.ps1'
        [System.IO.File]::WriteAllText($script:scriptFile, "Write-Output 'signed'`r`n")
        $script:workbookFile = Join-Path $signRoot 'Workbook.xlsm'
        Build-TestZip -Path $script:workbookFile -Entries 'xl/vbaProject.bin'
        foreach ($path in @($script:scriptFile, $script:workbookFile)) {
            $script:RowIndex[$path] = $script:Rows.Count
            $script:Rows.Add((ConvertTo-FileRow -Path $path -Status 'Ready' -Detail 'Macros found'))
        }

        # The key is persisted for signing but never added to a certificate store.
        $pfxPath = Join-Path $TestDrive 'signing.pfx'
        Build-TestPfx -Path $pfxPath -CodeSigning $true -Protection 'test-protection'
        $script:signingCertificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $pfxPath, 'test-protection', [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]'UserKeySet, PersistKeySet')
        Use-SigningCertificate -Certificate $script:signingCertificate
        $script:ui.TimestampBox.Text = ''

        Invoke-Signing
        $script:signCompleted = Wait-BackgroundJob
        $script:rowsByName = @{}
        foreach ($row in $script:Rows) {
            $script:rowsByName[$row.Name] = $row
        }
    }

    AfterAll {
        Use-SigningCertificate -Certificate $null
        if ($script:signingCertificate) {
            Clear-TestKey -Certificate $script:signingCertificate
        }
    }

    It 'completes and reports the outcome once' {
        $script:signCompleted | Should -BeTrue
        $script:shownMessages.Count | Should -Be 1
        $script:shownMessages[0] | Should -BeLike '*Signed 1 of 2 files*'
    }

    It 'signs a file whose path contains wildcard characters' {
        $script:rowsByName['Sample.ps1'].Status | Should -Be 'Signed'
        (Get-AuthenticodeSignature -LiteralPath $script:scriptFile).SignerCertificate.Thumbprint |
            Should -Be $script:signingCertificate.Thumbprint
    }

    It 'fails a workbook whose Office SIP is not registered without calling the signing API' {
        $script:rowsByName['Workbook.xlsm'].Status | Should -Be 'Failed'
        $script:rowsByName['Workbook.xlsm'].Detail | Should -BeLike 'Not signed: the Office SIP for .xlsm files is not registered*'
    }

    It 'leaves an unsigned workbook free for other processes' {
        { [System.IO.File]::Open($script:workbookFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None).Dispose() } |
            Should -Not -Throw
    }
}
