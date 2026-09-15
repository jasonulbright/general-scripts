#Requires -Version 5.1
<#
.SYNOPSIS
    Signs the VBA projects in Excel macro files with a code-signing certificate from the current user's store.

.DESCRIPTION
    Drop files or folders onto the window, or use Add files / Add folder. Folders are searched recursively
    for .xlsm, .xlsb, .xltm, .xlam, .xls, .xlt and .xla files. Files without a VBA project are listed as
    skipped. Sign signs every listed file that has macros.

    Signing uses Set-AuthenticodeSignature, which relies on the Microsoft Office Subject Interface Packages
    (msosipx.dll for Open XML formats, msosip.dll for legacy formats). The SIP must be registered for the
    same bitness as the PowerShell process running this tool.

.PARAMETER TimestampServer
    Authenticode timestamp server for new signatures. Pass an empty string to sign without a timestamp.

.EXAMPLE
    powershell.exe -NoProfile -STA -File .\Sign-ExcelMacros.ps1
#>
[CmdletBinding()]
param(
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    throw "WPF requires a single-threaded apartment. Start the tool with: powershell.exe -STA -File `"$PSCommandPath`""
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms
Import-Module -Name Microsoft.PowerShell.Security

$script:AppTitle          = 'Excel Macro Signer'
$script:ScriptPath        = $PSCommandPath
$script:OpenXmlExtensions = @('.xlsm', '.xlsb', '.xltm', '.xlam')
$script:LegacyExtensions  = @('.xls', '.xlt', '.xla')
$script:CodeSigningOid    = '1.3.6.1.5.5.7.3.3'
$script:SipDownloadUrl    = 'https://www.microsoft.com/download/details.aspx?id=56617'
$script:MainWindow        = $null
$script:Certificate       = $null
$script:Job               = $null
$script:StartupDone       = $false
$script:SipAction         = $null
$script:SipCurrent        = $null
$script:SignStats         = $null
$script:ScanUnreadable    = 0
$script:Rows              = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$script:RowIndex          = @{}

#region Background workers (run in their own runspace; they only talk to the UI through the queue)

$script:ScanWorker = {
    param(
        [string[]]$Paths,
        [string[]]$OpenXmlExtensions,
        [string[]]$LegacyExtensions,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$Queue
    )

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $extensions = @($OpenXmlExtensions) + @($LegacyExtensions)
    $unreadableFolders = 0

    foreach ($path in $Paths) {
        $walkErrors = $null
        if ([System.IO.Directory]::Exists($path)) {
            $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable walkErrors)
        }
        elseif ([System.IO.File]::Exists($path)) {
            $files = @(Get-Item -LiteralPath $path)
        }
        else {
            $files = @()
        }
        if ($walkErrors) {
            $unreadableFolders += $walkErrors.Count
        }

        foreach ($file in $files) {
            $extension = $file.Extension.ToLowerInvariant()
            # Office creates ~$<name> owner files beside open workbooks; they are not workbooks.
            if ($extensions -notcontains $extension -or $file.Name.StartsWith('~$')) {
                continue
            }

            $status = 'Ready'
            $detail = 'Macros found'
            try {
                $hasVba = $false
                if ($OpenXmlExtensions -contains $extension) {
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($file.FullName)
                    try {
                        foreach ($entry in $zip.Entries) {
                            if ($entry.FullName -like '*vbaProject.bin') {
                                $hasVba = $true
                                break
                            }
                        }
                    }
                    finally {
                        $zip.Dispose()
                    }
                }
                else {
                    # Compound-file directory entries hold UTF-16LE names at even byte offsets.
                    $content = [System.Text.Encoding]::Unicode.GetString([System.IO.File]::ReadAllBytes($file.FullName))
                    $hasVba = $content.Contains('_VBA_PROJECT_CUR')
                }

                if (-not $hasVba) {
                    $status = 'Skipped'
                    $detail = 'No VBA project'
                }
            }
            catch {
                $status = 'Skipped'
                $detail = "Could not read file (password-protected, damaged, or locked): $($_.Exception.Message)"
            }

            $Queue.Enqueue([pscustomobject]@{
                Kind   = 'File'
                Path   = $file.FullName
                Status = $status
                Detail = $detail
            })
        }
    }

    $Queue.Enqueue([pscustomobject]@{
        Kind              = 'ScanDone'
        UnreadableFolders = $unreadableFolders
    })
}

$script:SignWorker = {
    param(
        [string[]]$Paths,
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [string]$TimestampServer,
        [System.Collections.Concurrent.ConcurrentQueue[object]]$Queue
    )

    Import-Module -Name Microsoft.PowerShell.Security

    foreach ($path in $Paths) {
        $status = 'Failed'
        $detail = ''
        try {
            # Windows PowerShell 5.1 signs with SHA1 when HashAlgorithm is omitted.
            $signParams = @{
                LiteralPath   = $path
                Certificate   = $Certificate
                HashAlgorithm = 'SHA256'
                ErrorAction   = 'Stop'
            }
            if ($TimestampServer) {
                $signParams.TimestampServer = $TimestampServer
            }

            $signature = Set-AuthenticodeSignature @signParams

            if ($signature.SignerCertificate -and $signature.SignerCertificate.Thumbprint -eq $Certificate.Thumbprint) {
                $status = 'Signed'
                if ($signature.Status -eq 'Valid') {
                    $detail = 'Signed and verified'
                }
                else {
                    $detail = "Signed; verification on this PC: $($signature.StatusMessage)"
                }
            }
            else {
                $detail = "$($signature.Status): $($signature.StatusMessage)"
            }
        }
        catch {
            $detail = $_.Exception.Message
        }

        $Queue.Enqueue([pscustomobject]@{
            Kind   = 'Signed'
            Path   = $path
            Status = $status
            Detail = $detail
        })
    }
}

#endregion

#region Certificates, SIP registration, environment

function Test-CodeSigningUsage {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    foreach ($extension in $Certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($oid in $extension.EnhancedKeyUsages) {
                if ($oid.Value -eq $script:CodeSigningOid) {
                    return $true
                }
            }
        }
    }
    return $false
}

function Get-SigningCertificate {
    $now = Get-Date
    Get-ChildItem -Path Cert:\CurrentUser\My -CodeSigningCert |
        Where-Object { $_.HasPrivateKey -and $_.NotBefore -le $now -and $_.NotAfter -gt $now -and (Test-CodeSigningUsage -Certificate $_) } |
        Sort-Object -Property NotAfter -Descending
}

function Get-CertificateLabel {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $nameType = [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName
    [pscustomobject]@{
        IssuedTo    = $Certificate.GetNameInfo($nameType, $false)
        IssuedBy    = $Certificate.GetNameInfo($nameType, $true)
        Expires     = $Certificate.NotAfter.ToString('yyyy-MM-dd')
        Thumbprint  = $Certificate.Thumbprint
        Certificate = $Certificate
    }
}

function Import-PfxToUserStore {
    param(
        [string]$Path,
        [System.Security.SecureString]$Password
    )

    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]

    # Without PersistKeySet the private key is removed on Dispose, so a rejected file leaves no key behind.
    $probe = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Path, $Password, $flags::UserKeySet)
    try {
        if (-not $probe.HasPrivateKey) {
            throw 'The file does not contain a private key.'
        }
        if (-not (Test-CodeSigningUsage -Certificate $probe)) {
            throw 'The certificate is not valid for code signing (the Code Signing enhanced key usage is missing).'
        }
        $now = Get-Date
        if ($probe.NotBefore -gt $now -or $probe.NotAfter -le $now) {
            throw "The certificate is not currently valid ($($probe.NotBefore.ToString('yyyy-MM-dd')) to $($probe.NotAfter.ToString('yyyy-MM-dd')))."
        }
    }
    finally {
        $probe.Dispose()
    }

    $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($Path, $Password, ($flags::UserKeySet -bor $flags::PersistKeySet))
    $store = [System.Security.Cryptography.X509Certificates.X509Store]::new(
        [System.Security.Cryptography.X509Certificates.StoreName]::My,
        [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser)
    $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    try {
        $store.Add($certificate)
    }
    finally {
        $store.Close()
    }
    $certificate
}

function Get-OfficeSipRegistration {
    $subKeyPath = 'SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CryptSIPDllPutSignedDataMsg'
    $views = [System.Collections.Generic.List[Microsoft.Win32.RegistryView]]::new()
    $views.Add([Microsoft.Win32.RegistryView]::Registry32)
    if ([Environment]::Is64BitOperatingSystem) {
        $views.Add([Microsoft.Win32.RegistryView]::Registry64)
    }

    foreach ($view in $views) {
        $openXml = $false
        $legacy = $false
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
        try {
            $sipKey = $baseKey.OpenSubKey($subKeyPath)
            if ($sipKey) {
                try {
                    foreach ($name in $sipKey.GetSubKeyNames()) {
                        $providerKey = $sipKey.OpenSubKey($name)
                        if (-not $providerKey) {
                            continue
                        }
                        try {
                            $dll = [string]$providerKey.GetValue('Dll')
                            if ($dll -match 'msosipx\.dll') {
                                $openXml = $true
                            }
                            elseif ($dll -match 'msosip\.dll') {
                                $legacy = $true
                            }
                        }
                        finally {
                            $providerKey.Close()
                        }
                    }
                }
                finally {
                    $sipKey.Close()
                }
            }
        }
        finally {
            $baseKey.Close()
        }

        [pscustomobject]@{
            Is64Bit = ($view -eq [Microsoft.Win32.RegistryView]::Registry64)
            OpenXml = $openXml
            Legacy  = $legacy
        }
    }
}

function Test-IsElevated {
    $principal = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Message {
    param(
        [string]$Text,
        [System.Windows.MessageBoxImage]$Icon = [System.Windows.MessageBoxImage]::Information,
        [System.Windows.MessageBoxButton]$Buttons = [System.Windows.MessageBoxButton]::OK,
        [System.Windows.Window]$Owner = $script:MainWindow
    )

    if ($Owner -and $Owner.IsVisible) {
        return [System.Windows.MessageBox]::Show($Owner, $Text, $script:AppTitle, $Buttons, $Icon)
    }
    [System.Windows.MessageBox]::Show($Text, $script:AppTitle, $Buttons, $Icon)
}

function Invoke-Safely {
    param([scriptblock]$Action)

    try {
        & $Action
    }
    catch {
        [void](Show-Message -Text $_.Exception.Message -Icon Error)
    }
}

#endregion

#region Dialogs

$script:PasswordXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Certificate password" Width="440" SizeToContent="Height" ResizeMode="NoResize"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Segoe UI" FontSize="13" Background="#FFF5F6F8">
  <StackPanel Margin="18">
    <TextBlock x:Name="PromptText" TextWrapping="Wrap" Margin="0,0,0,10"/>
    <PasswordBox x:Name="PasswordInput" Padding="4,3"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="OkButton" Content="Import" IsDefault="True" MinWidth="90" Padding="12,4" Margin="0,0,8,0"/>
      <Button Content="Cancel" IsCancel="True" MinWidth="90" Padding="12,4"/>
    </StackPanel>
  </StackPanel>
</Window>
'@

$script:PickerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Select signing certificate" Width="860" Height="380" MinWidth="620" MinHeight="280"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        FontFamily="Segoe UI" FontSize="13" Background="#FFF5F6F8">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="PickerMessage" TextWrapping="Wrap" Margin="0,0,0,10"/>
    <ListView x:Name="CertList" Grid.Row="1" SelectionMode="Single" Background="White" Foreground="#FF1F2933">
      <ListView.View>
        <GridView>
          <GridViewColumn Header="Issued to" Width="200" DisplayMemberBinding="{Binding IssuedTo}"/>
          <GridViewColumn Header="Issued by" Width="170" DisplayMemberBinding="{Binding IssuedBy}"/>
          <GridViewColumn Header="Expires" Width="90" DisplayMemberBinding="{Binding Expires}"/>
          <GridViewColumn Header="Thumbprint" Width="330" DisplayMemberBinding="{Binding Thumbprint}"/>
        </GridView>
      </ListView.View>
    </ListView>
    <DockPanel Grid.Row="2" Margin="0,12,0,0" LastChildFill="False">
      <Button x:Name="ImportButton" DockPanel.Dock="Left" Content="Import .pfx..." MinWidth="110" Padding="12,4"/>
      <Button DockPanel.Dock="Right" Content="Cancel" IsCancel="True" MinWidth="90" Padding="12,4"/>
      <Button x:Name="UseButton" DockPanel.Dock="Right" Content="Use selected" IsDefault="True" MinWidth="110" Padding="12,4" Margin="0,0,8,0"/>
    </DockPanel>
  </Grid>
</Window>
'@

function ConvertFrom-XamlWindow {
    param(
        [string]$Xaml,
        [System.Windows.Window]$Owner
    )

    $window = [System.Windows.Markup.XamlReader]::Parse($Xaml)
    if ($Owner -and $Owner.IsVisible) {
        $window.Owner = $Owner
    }
    else {
        $window.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }
    $window
}

function Read-PfxPassword {
    param(
        [string]$FileName,
        [System.Windows.Window]$Owner
    )

    $dialog = ConvertFrom-XamlWindow -Xaml $script:PasswordXaml -Owner $Owner
    $passwordInput = $dialog.FindName('PasswordInput')
    $dialog.FindName('PromptText').Text = "Enter the password for $FileName"
    $captured = @{ Password = $null }

    $dialog.FindName('OkButton').Add_Click({
        $captured.Password = $passwordInput.SecurePassword
        $dialog.DialogResult = $true
    })
    $dialog.Add_ContentRendered({ [void]$passwordInput.Focus() })

    if ($dialog.ShowDialog() -eq $true) {
        return $captured.Password
    }
    return $null
}

function Invoke-PfxImport {
    param([System.Windows.Window]$Owner)

    $fileDialog = [Microsoft.Win32.OpenFileDialog]::new()
    $fileDialog.Title = 'Select the code-signing certificate (.pfx) to import'
    $fileDialog.Filter = 'Certificate with private key (*.pfx;*.p12)|*.pfx;*.p12'
    if ($fileDialog.ShowDialog() -ne $true) {
        return $null
    }

    $password = Read-PfxPassword -FileName ([System.IO.Path]::GetFileName($fileDialog.FileName)) -Owner $Owner
    if ($null -eq $password) {
        return $null
    }

    try {
        $certificate = Import-PfxToUserStore -Path $fileDialog.FileName -Password $password
        [void](Show-Message -Owner $Owner -Text "Imported '$($certificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false))' into your personal certificate store.")
        return $certificate
    }
    catch {
        [void](Show-Message -Owner $Owner -Icon Error -Text "Import failed: $($_.Exception.Message)")
        return $null
    }
    finally {
        $password.Dispose()
    }
}

function Show-CertificatePicker {
    param([System.Windows.Window]$Owner)

    $dialog = ConvertFrom-XamlWindow -Xaml $script:PickerXaml -Owner $Owner
    $list = $dialog.FindName('CertList')
    $message = $dialog.FindName('PickerMessage')
    $useButton = $dialog.FindName('UseButton')
    $state = @{ Selected = $null }

    $refresh = {
        param([string]$SelectThumbprint)

        $labels = @(Get-SigningCertificate | ForEach-Object { Get-CertificateLabel -Certificate $_ })
        $list.ItemsSource = $labels
        $useButton.IsEnabled = $labels.Count -gt 0
        if ($labels.Count -eq 0) {
            $message.Text = 'No valid code-signing certificate with a private key is in your personal certificate store. Import a .pfx file to continue.'
            return
        }

        $message.Text = "Select the certificate to sign with ($($labels.Count) available)."
        $list.SelectedIndex = 0
        foreach ($label in $labels) {
            if ($label.Thumbprint -eq $SelectThumbprint) {
                $list.SelectedItem = $label
            }
        }
    }

    $accept = {
        if ($list.SelectedItem) {
            $state.Selected = $list.SelectedItem.Certificate
            $dialog.DialogResult = $true
        }
    }
    $useButton.Add_Click($accept)
    $list.Add_MouseDoubleClick($accept)

    $dialog.FindName('ImportButton').Add_Click({
        $imported = Invoke-PfxImport -Owner $dialog
        if ($imported) {
            & $refresh $imported.Thumbprint
        }
    })

    & $refresh ''
    if ($dialog.ShowDialog() -eq $true) {
        return $state.Selected
    }
    return $null
}

function Select-SigningCertificate {
    param([System.Windows.Window]$Owner)

    $certificates = @(Get-SigningCertificate)
    if ($certificates.Count -eq 1) {
        return $certificates[0]
    }

    if ($certificates.Count -eq 0) {
        $answer = Show-Message -Owner $Owner -Icon Question -Buttons YesNo -Text ("No valid code-signing certificate with a private key was found in your personal certificate store (Cert:\CurrentUser\My).`n`n" +
            'Select a .pfx file to import now?')
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
            return $null
        }
        [void](Invoke-PfxImport -Owner $Owner)
        $certificates = @(Get-SigningCertificate)
        if ($certificates.Count -eq 0) {
            return $null
        }
        if ($certificates.Count -eq 1) {
            return $certificates[0]
        }
    }

    Show-CertificatePicker -Owner $Owner
}

#endregion

#region Background job plumbing

$script:JobTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:JobTimer.Interval = [TimeSpan]::FromMilliseconds(150)

function Invoke-BackgroundJob {
    param(
        [scriptblock]$Worker,
        [hashtable]$Parameters,
        [scriptblock]$OnMessage,
        [scriptblock]$OnComplete
    )

    $queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = [System.Threading.ApartmentState]::STA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $runspace.Open()

    $powershell = [powershell]::Create()
    $powershell.Runspace = $runspace
    # Added as text so the worker binds to its own runspace; UI objects never cross threads.
    [void]$powershell.AddScript($Worker.ToString())
    foreach ($name in $Parameters.Keys) {
        [void]$powershell.AddParameter($name, $Parameters[$name])
    }
    [void]$powershell.AddParameter('Queue', $queue)

    $script:Job = [pscustomobject]@{
        PowerShell   = $powershell
        Runspace     = $runspace
        Queue        = $queue
        OnMessage    = $OnMessage
        OnComplete   = $OnComplete
        MessageError = $null
        Handle       = $powershell.BeginInvoke()
    }
    $script:JobTimer.Start()
}

function Receive-BackgroundJob {
    $job = $script:Job
    if ($null -eq $job) {
        $script:JobTimer.Stop()
        return
    }

    # Sampled before draining: once the pipeline has completed, every message is already queued.
    $finished = $job.Handle.IsCompleted
    $message = $null
    while ($job.Queue.TryDequeue([ref]$message)) {
        try {
            & $job.OnMessage $message
        }
        catch {
            if (-not $job.MessageError) {
                $job.MessageError = $_.Exception.Message
            }
        }
    }
    if (-not $finished) {
        return
    }

    $script:JobTimer.Stop()
    $script:Job = $null
    $failure = $job.MessageError
    try {
        [void]$job.PowerShell.EndInvoke($job.Handle)
        if (-not $failure -and $job.PowerShell.Streams.Error.Count -gt 0) {
            $failure = $job.PowerShell.Streams.Error[0].ToString()
        }
    }
    catch {
        $failure = $_.Exception.Message
    }
    finally {
        $job.PowerShell.Dispose()
        $job.Runspace.Dispose()
    }
    & $job.OnComplete $failure
}

$script:JobTimer.Add_Tick({
    try {
        Receive-BackgroundJob
    }
    catch {
        [void](Show-Message -Icon Error -Text "Background task error: $($_.Exception.Message)")
    }
})

#endregion

#region Main window

$script:MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Excel Macro Signer" Width="960" Height="640" MinWidth="720" MinHeight="480"
        WindowStartupLocation="CenterScreen" AllowDrop="True"
        FontFamily="Segoe UI" FontSize="13" Background="#FFF5F6F8">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Padding" Value="14,5"/>
      <Setter Property="MinWidth" Value="90"/>
    </Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="White" BorderBrush="#FFD5D9E0" BorderThickness="1" CornerRadius="4" Padding="12,8">
      <DockPanel>
        <Button x:Name="ChangeCertButton" DockPanel.Dock="Right" Content="Change..." VerticalAlignment="Center"/>
        <StackPanel VerticalAlignment="Center" Margin="0,0,12,0">
          <TextBlock Text="Signing certificate" FontSize="11" Foreground="#FF5F6B7A"/>
          <TextBlock x:Name="CertText" FontSize="14" FontWeight="SemiBold" TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="CertDetailText" FontSize="11" Foreground="#FF5F6B7A" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <Border x:Name="SipBanner" Grid.Row="1" Margin="0,10,0,0" Background="#FFFFF4E5" BorderBrush="#FFF0B45A"
            BorderThickness="1" CornerRadius="4" Padding="12,8" Visibility="Collapsed">
      <DockPanel>
        <Button x:Name="SipActionButton" DockPanel.Dock="Right" VerticalAlignment="Center" Margin="12,0,0,0"/>
        <TextBlock x:Name="SipText" TextWrapping="Wrap" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>

    <Grid Grid.Row="2" Margin="0,10,0,0" MinHeight="120">
      <Rectangle Stroke="#FF9AA5B1" StrokeThickness="1.5" StrokeDashArray="5 3" RadiusX="6" RadiusY="6" Fill="White"/>
      <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Margin="16,12">
        <TextBlock Text="Drop Excel files or folders anywhere in this window" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center"/>
        <TextBlock x:Name="DropHint" Foreground="#FF5F6B7A" Margin="0,4,0,10" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
          <Button x:Name="AddFilesButton" Content="Add files..." Margin="0,0,8,0"/>
          <Button x:Name="AddFolderButton" Content="Add folder..." Margin="0,0,8,0"/>
          <Button x:Name="ClearButton" Content="Clear list"/>
        </StackPanel>
      </StackPanel>
    </Grid>

    <DataGrid x:Name="FileGrid" Grid.Row="3" Margin="0,10,0,0" AutoGenerateColumns="False" IsReadOnly="True"
              CanUserAddRows="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal"
              HorizontalGridLinesBrush="#FFE6E9EE" SelectionMode="Extended" Background="White" BorderBrush="#FFD5D9E0">
      <DataGrid.Columns>
        <DataGridTextColumn Header="Status" Binding="{Binding Status}" Width="80">
          <DataGridTextColumn.ElementStyle>
            <Style TargetType="TextBlock">
              <Setter Property="FontWeight" Value="SemiBold"/>
              <Setter Property="Margin" Value="4,2"/>
              <Style.Triggers>
                <DataTrigger Binding="{Binding Status}" Value="Signed">
                  <Setter Property="Foreground" Value="#FF1E7B34"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding Status}" Value="Failed">
                  <Setter Property="Foreground" Value="#FFC42B1C"/>
                </DataTrigger>
                <DataTrigger Binding="{Binding Status}" Value="Skipped">
                  <Setter Property="Foreground" Value="#FF7A8594"/>
                </DataTrigger>
              </Style.Triggers>
            </Style>
          </DataGridTextColumn.ElementStyle>
        </DataGridTextColumn>
        <DataGridTextColumn Header="File" Binding="{Binding Name}" Width="220">
          <DataGridTextColumn.ElementStyle>
            <Style TargetType="TextBlock">
              <Setter Property="Margin" Value="4,2"/>
              <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
              <Setter Property="ToolTip" Value="{Binding Path}"/>
            </Style>
          </DataGridTextColumn.ElementStyle>
        </DataGridTextColumn>
        <DataGridTextColumn Header="Details" Binding="{Binding Detail}" Width="*">
          <DataGridTextColumn.ElementStyle>
            <Style TargetType="TextBlock">
              <Setter Property="Margin" Value="4,2"/>
              <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
              <Setter Property="ToolTip" Value="{Binding Detail}"/>
            </Style>
          </DataGridTextColumn.ElementStyle>
        </DataGridTextColumn>
        <DataGridTextColumn Header="Folder" Binding="{Binding Folder}" Width="260">
          <DataGridTextColumn.ElementStyle>
            <Style TargetType="TextBlock">
              <Setter Property="Margin" Value="4,2"/>
              <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
              <Setter Property="ToolTip" Value="{Binding Folder}"/>
            </Style>
          </DataGridTextColumn.ElementStyle>
        </DataGridTextColumn>
      </DataGrid.Columns>
    </DataGrid>

    <Grid Grid.Row="4" Margin="0,12,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="240"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Text="Timestamp server" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBox x:Name="TimestampBox" Grid.Column="1" VerticalContentAlignment="Center" Padding="4,3"
               ToolTip="Leave empty to sign without a timestamp."/>
      <TextBlock x:Name="SummaryText" Grid.Column="2" VerticalAlignment="Center" Margin="12,0" Foreground="#FF5F6B7A" TextTrimming="CharacterEllipsis"/>
      <Button x:Name="SignButton" Grid.Column="3" Content="Sign 0 files" FontWeight="SemiBold" Padding="22,7" IsEnabled="False"/>
      <ProgressBar x:Name="Progress" Grid.Row="1" Grid.ColumnSpan="4" Height="6" Margin="0,10,0,0" Visibility="Hidden"/>
    </Grid>
  </Grid>
</Window>
'@

function ConvertTo-FileRow {
    param(
        [string]$Path,
        [string]$Status,
        [string]$Detail
    )

    [pscustomobject]@{
        Status = $Status
        Name   = [System.IO.Path]::GetFileName($Path)
        Detail = $Detail
        Folder = [System.IO.Path]::GetDirectoryName($Path)
        Path   = $Path
    }
}

function Sync-SignButton {
    $ready = 0
    $signed = 0
    $failed = 0
    $skipped = 0
    foreach ($row in $script:Rows) {
        switch ($row.Status) {
            'Ready'   { $ready++ }
            'Signed'  { $signed++ }
            'Failed'  { $failed++ }
            'Skipped' { $skipped++ }
        }
    }

    $pending = $ready + $failed
    $idle = $null -eq $script:Job
    if ($pending -eq 1) {
        $script:ui.SignButton.Content = 'Sign 1 file'
    }
    else {
        $script:ui.SignButton.Content = "Sign $pending files"
    }
    $script:ui.SignButton.IsEnabled = $idle -and $pending -gt 0 -and $null -ne $script:Certificate

    if ($idle) {
        if ($script:Rows.Count -eq 0) {
            $script:ui.SummaryText.Text = 'No files added yet.'
        }
        else {
            $script:ui.SummaryText.Text = "$($script:Rows.Count) files: $ready ready, $signed signed, $failed failed, $skipped skipped"
        }
    }
}

function Switch-BusyState {
    param(
        [bool]$Busy,
        [int]$Maximum = 0
    )

    foreach ($name in 'AddFilesButton', 'AddFolderButton', 'ClearButton', 'ChangeCertButton', 'TimestampBox', 'SipActionButton') {
        $script:ui[$name].IsEnabled = -not $Busy
    }

    $progress = $script:ui.Progress
    $progress.IsIndeterminate = $Busy -and $Maximum -eq 0
    $progress.Maximum = [Math]::Max(1, $Maximum)
    $progress.Value = 0
    if ($Busy) {
        $progress.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $progress.Visibility = [System.Windows.Visibility]::Hidden
    }
    Sync-SignButton
}

function Use-SigningCertificate {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $script:Certificate = $Certificate
    if ($Certificate) {
        $label = Get-CertificateLabel -Certificate $Certificate
        $script:ui.CertText.Text = $label.IssuedTo
        $script:ui.CertText.ClearValue([System.Windows.Controls.TextBlock]::ForegroundProperty)
        $script:ui.CertDetailText.Text = "Issued by $($label.IssuedBy)   |   Expires $($label.Expires)   |   Thumbprint $($label.Thumbprint)"
    }
    else {
        $script:ui.CertText.Text = 'No signing certificate selected'
        $script:ui.CertText.Foreground = [System.Windows.Media.Brushes]::Firebrick
        $script:ui.CertDetailText.Text = 'Choose Change... to select or import a code-signing certificate.'
    }
    Sync-SignButton
}

function Show-SipStatus {
    $processIs64 = [Environment]::Is64BitProcess
    $registrations = @(Get-OfficeSipRegistration)
    $current = $registrations | Where-Object { $_.Is64Bit -eq $processIs64 } | Select-Object -First 1
    $other = $registrations | Where-Object { $_.Is64Bit -ne $processIs64 } | Select-Object -First 1
    $bits = if ($processIs64) { '64-bit' } else { '32-bit' }
    $script:SipCurrent = $current
    $currentAny = $current -and ($current.OpenXml -or $current.Legacy)
    $otherAny = $other -and ($other.OpenXml -or $other.Legacy)

    if ($current -and $current.OpenXml -and $current.Legacy) {
        $script:SipAction = $null
        $script:ui.SipBanner.Visibility = [System.Windows.Visibility]::Collapsed
        return
    }

    if (-not $currentAny -and $otherAny) {
        $otherBits = if ($other.Is64Bit) { '64-bit' } else { '32-bit' }
        $script:SipAction = 'Relaunch'
        $script:ui.SipText.Text = "The Office signing add-in (SIP) is registered for $otherBits processes only, and this is $bits PowerShell. Signing fails until the tool runs in $otherBits Windows PowerShell."
        $script:ui.SipActionButton.Content = "Restart as $otherBits"
    }
    elseif (-not $currentAny) {
        $script:SipAction = 'Download'
        $script:ui.SipText.Text = "The Office signing add-in (SIP) is not registered for $bits processes on this PC. Install 'Microsoft Office Subject Interface Packages for Digitally Signing VBA Projects' ($bits build) and register msosipx.dll and msosip.dll with regsvr32 as its readme describes."
        $script:ui.SipActionButton.Content = 'Open download page'
    }
    else {
        $missing = if (-not $current.OpenXml) { 'msosipx.dll (.xlsm, .xlsb, .xltm, .xlam)' } else { 'msosip.dll (.xls, .xlt, .xla)' }
        $script:SipAction = 'Download'
        $script:ui.SipText.Text = "Part of the Office signing add-in (SIP) is not registered for $bits processes: $missing. Files of those types will fail to sign."
        $script:ui.SipActionButton.Content = 'Open download page'
    }
    $script:ui.SipBanner.Visibility = [System.Windows.Visibility]::Visible
}

function Get-SipGap {
    param([string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($script:OpenXmlExtensions -contains $extension) {
        $covered = [bool]($script:SipCurrent -and $script:SipCurrent.OpenXml)
    }
    elseif ($script:LegacyExtensions -contains $extension) {
        $covered = [bool]($script:SipCurrent -and $script:SipCurrent.Legacy)
    }
    else {
        $covered = $true
    }
    if ($covered) {
        return $null
    }

    $bits = if ([Environment]::Is64BitProcess) { '64-bit' } else { '32-bit' }
    "Not signed: the Office SIP for $extension files is not registered for $bits PowerShell."
}

function Invoke-BitnessRelaunch {
    if (-not $script:ScriptPath) {
        [void](Show-Message -Icon Warning -Text 'Start the tool from its .ps1 file to use Restart.')
        return
    }

    $folder = if ([Environment]::Is64BitProcess) { 'SysWOW64' } else { 'Sysnative' }
    $powershellExe = Join-Path -Path $env:windir -ChildPath "$folder\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = @('-NoProfile', '-STA', '-File', "`"$script:ScriptPath`"")
    $timestamp = $script:ui.TimestampBox.Text.Trim()
    if ($timestamp) {
        $arguments += @('-TimestampServer', "`"$timestamp`"")
    }
    Start-Process -FilePath $powershellExe -ArgumentList $arguments
    $script:MainWindow.Close()
}

function Add-InputPath {
    param([string[]]$Path)

    $paths = @($Path | Where-Object { $_ })
    if ($script:Job -or $paths.Count -eq 0) {
        return
    }

    $script:ScanUnreadable = 0
    $script:ScanAdded = 0
    Switch-BusyState -Busy $true
    $script:ui.SummaryText.Text = 'Searching for Excel macro files...'

    Invoke-BackgroundJob -Worker $script:ScanWorker -Parameters @{
        Paths             = [string[]]$paths
        OpenXmlExtensions = [string[]]$script:OpenXmlExtensions
        LegacyExtensions  = [string[]]$script:LegacyExtensions
    } -OnMessage {
        param($Message)

        if ($Message.Kind -eq 'ScanDone') {
            $script:ScanUnreadable = $Message.UnreadableFolders
            return
        }
        if ($script:RowIndex.ContainsKey($Message.Path)) {
            return
        }
        $script:RowIndex[$Message.Path] = $script:Rows.Count
        $script:Rows.Add((ConvertTo-FileRow -Path $Message.Path -Status $Message.Status -Detail $Message.Detail))
        $script:ScanAdded++
        $script:ui.SummaryText.Text = "Searching... $($script:ScanAdded) files found"
    } -OnComplete {
        param($Failure)

        Switch-BusyState -Busy $false
        $notes = @()
        if ($script:ScanAdded -eq 0) {
            $notes += 'No new Excel macro files were found.'
        }
        if ($script:ScanUnreadable -gt 0) {
            $notes += "$($script:ScanUnreadable) items could not be read (access denied or path too long)."
        }
        if ($Failure) {
            $notes += "Search error: $Failure"
        }
        if ($notes.Count -gt 0) {
            [void](Show-Message -Icon Warning -Text ($notes -join "`n"))
        }
    }
}

function Invoke-Signing {
    if ($script:Job -or $null -eq $script:Certificate) {
        return
    }

    $certificate = $script:Certificate
    if ($certificate.NotAfter -le (Get-Date)) {
        [void](Show-Message -Icon Warning -Text 'The selected certificate has expired. Choose Change... to select another one.')
        return
    }

    $timestamp = $script:ui.TimestampBox.Text.Trim()
    if ($timestamp -and $timestamp -notmatch '^https?://') {
        [void](Show-Message -Icon Warning -Text 'The timestamp server must start with http:// or https://, or be left empty.')
        return
    }

    $candidates = @($script:Rows | Where-Object { $_.Status -eq 'Ready' -or $_.Status -eq 'Failed' } | ForEach-Object { $_.Path })
    if ($candidates.Count -eq 0) {
        return
    }

    Show-SipStatus
    $paths = [System.Collections.Generic.List[string]]::new()
    $notAttempted = 0
    foreach ($path in $candidates) {
        # Set-AuthenticodeSignature keeps a file with no registered SIP open in this process until the process exits.
        $gap = Get-SipGap -Path $path
        if ($gap) {
            $script:Rows[$script:RowIndex[$path]] = ConvertTo-FileRow -Path $path -Status 'Failed' -Detail $gap
            $notAttempted++
        }
        else {
            $paths.Add($path)
        }
    }

    if ($paths.Count -eq 0) {
        Sync-SignButton
        [void](Show-Message -Icon Warning -Text 'No files were signed. The Office SIP for these file types is not registered for this PowerShell process; the banner at the top of the window shows how to fix it.')
        return
    }

    $script:SignStats = @{
        Total        = $candidates.Count
        Done         = $notAttempted
        Signed       = 0
        Failed       = $notAttempted
        NotAttempted = $notAttempted
        Timestamp    = $timestamp
    }
    Switch-BusyState -Busy $true -Maximum $candidates.Count
    $script:ui.Progress.Value = $notAttempted
    $script:ui.SummaryText.Text = "Signing $notAttempted of $($candidates.Count)..."

    Invoke-BackgroundJob -Worker $script:SignWorker -Parameters @{
        Paths           = $paths.ToArray()
        Certificate     = $certificate
        TimestampServer = $timestamp
    } -OnMessage {
        param($Message)

        $index = $script:RowIndex[$Message.Path]
        if ($null -ne $index) {
            $script:Rows[$index] = ConvertTo-FileRow -Path $Message.Path -Status $Message.Status -Detail $Message.Detail
        }
        $stats = $script:SignStats
        $stats.Done++
        if ($Message.Status -eq 'Signed') {
            $stats.Signed++
        }
        else {
            $stats.Failed++
        }
        $script:ui.Progress.Value = $stats.Done
        $script:ui.SummaryText.Text = "Signing $($stats.Done) of $($stats.Total)..."
    } -OnComplete {
        param($Failure)

        Switch-BusyState -Busy $false
        $stats = $script:SignStats
        $text = "Signed $($stats.Signed) of $($stats.Total) files."
        $icon = [System.Windows.MessageBoxImage]::Information
        if ($stats.Failed -gt 0) {
            $icon = [System.Windows.MessageBoxImage]::Warning
            $text += " $($stats.Failed) failed; the Details column shows why."
            if ($stats.Signed -eq 0 -and $stats.Failed -gt $stats.NotAttempted -and $stats.Timestamp) {
                $text += "`n`nIf this PC cannot reach $($stats.Timestamp), clear the timestamp server box and sign again."
            }
        }
        if ($Failure) {
            $icon = [System.Windows.MessageBoxImage]::Error
            $text += "`n`nSigning stopped early: $Failure"
        }
        [void](Show-Message -Icon $icon -Text $text)
    }
}

#endregion

#region Startup

$window = [System.Windows.Markup.XamlReader]::Parse($script:MainXaml)
$script:MainWindow = $window
$script:ui = @{}
foreach ($name in 'CertText', 'CertDetailText', 'ChangeCertButton', 'SipBanner', 'SipText', 'SipActionButton', 'DropHint',
                  'AddFilesButton', 'AddFolderButton', 'ClearButton', 'FileGrid', 'TimestampBox', 'SummaryText', 'SignButton', 'Progress') {
    $script:ui[$name] = $window.FindName($name)
}

$script:ui.FileGrid.ItemsSource = $script:Rows
$script:ui.TimestampBox.Text = $TimestampServer
$script:ui.DropHint.Text = 'Folders are searched recursively for .xlsm .xlsb .xltm .xlam .xls .xlt .xla. Files without macros are skipped.'
if (Test-IsElevated) {
    # UIPI drops OLE drag-and-drop from medium-integrity Explorer into an elevated window.
    $script:ui.DropHint.Text += "`nRunning as administrator: Windows blocks drag-and-drop from Explorer into elevated windows. Use the buttons, or start the tool without elevation."
    $script:ui.DropHint.Foreground = [System.Windows.Media.Brushes]::Firebrick
}
Show-SipStatus
Use-SigningCertificate -Certificate $null

# Handlers resolve script-scope functions and $script: state when they run; .GetNewClosure() rebinds them to a new module scope where neither exists.
$dragFeedback = {
    $dragArgs = [System.Windows.DragEventArgs]$args[1]

    if ($null -eq $script:Job -and $dragArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $dragArgs.Effects = [System.Windows.DragDropEffects]::Copy
    }
    else {
        $dragArgs.Effects = [System.Windows.DragDropEffects]::None
    }
    $dragArgs.Handled = $true
}
$window.Add_PreviewDragEnter($dragFeedback)
$window.Add_PreviewDragOver($dragFeedback)

$window.Add_PreviewDrop({
    $dropArgs = [System.Windows.DragEventArgs]$args[1]

    $dropArgs.Handled = $true
    if ($dropArgs.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) {
        $dropped = [string[]]$dropArgs.Data.GetData([System.Windows.DataFormats]::FileDrop)
        Invoke-Safely { Add-InputPath -Path $dropped }
    }
})

$script:ui.AddFilesButton.Add_Click({
    Invoke-Safely {
        $dialog = [Microsoft.Win32.OpenFileDialog]::new()
        $dialog.Title = 'Select Excel macro files'
        $dialog.Multiselect = $true
        $dialog.Filter = 'Excel macro files (*.xlsm;*.xlsb;*.xltm;*.xlam;*.xls;*.xlt;*.xla)|*.xlsm;*.xlsb;*.xltm;*.xlam;*.xls;*.xlt;*.xla|All files (*.*)|*.*'
        if ($dialog.ShowDialog($script:MainWindow) -eq $true) {
            Add-InputPath -Path $dialog.FileNames
        }
    }
})

$script:ui.AddFolderButton.Add_Click({
    Invoke-Safely {
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        try {
            $dialog.Description = 'Select a folder to search for Excel macro files (subfolders included)'
            $dialog.ShowNewFolderButton = $false
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                Add-InputPath -Path @($dialog.SelectedPath)
            }
        }
        finally {
            $dialog.Dispose()
        }
    }
})

$script:ui.ClearButton.Add_Click({
    $script:Rows.Clear()
    $script:RowIndex.Clear()
    Sync-SignButton
})

$script:ui.ChangeCertButton.Add_Click({
    Invoke-Safely {
        $picked = Show-CertificatePicker -Owner $script:MainWindow
        if ($picked) {
            Use-SigningCertificate -Certificate $picked
        }
    }
})

$script:ui.SipActionButton.Add_Click({
    Invoke-Safely {
        switch ($script:SipAction) {
            'Relaunch' { Invoke-BitnessRelaunch }
            'Download' { Start-Process -FilePath $script:SipDownloadUrl }
        }
    }
})

$script:ui.SignButton.Add_Click({
    Invoke-Safely { Invoke-Signing }
})

$window.Add_ContentRendered({
    if ($script:StartupDone) {
        return
    }
    $script:StartupDone = $true
    Invoke-Safely {
        Use-SigningCertificate -Certificate (Select-SigningCertificate -Owner $script:MainWindow)
    }
})

$window.Add_Closing({
    $closingArgs = [System.ComponentModel.CancelEventArgs]$args[1]

    if ($script:Job) {
        $closingArgs.Cancel = $true
        [void](Show-Message -Icon Warning -Text 'Wait for the current search or signing run to finish before closing.')
    }
})

[void]$window.ShowDialog()

#endregion
