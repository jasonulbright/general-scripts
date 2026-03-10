# ElevatedLauncher.ps1
# GUI utility for launching applications under alternate (elevated) credentials.
# Credentials are stored AES-encrypted on disk. Application list is persisted
# in a JSON config file alongside this script.
#
# Files created in $PSScriptRoot:
#   launcher.key  - 256-bit AES key
#   launcher.cred - encrypted credential (username + password)
#   launcher.json - saved application list

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$configPath = Join-Path $PSScriptRoot 'launcher.json'
$keyPath    = Join-Path $PSScriptRoot 'launcher.key'
$credPath   = Join-Path $PSScriptRoot 'launcher.cred'

# --- Load app list from config ---
function Get-AppList {
    if (Test-Path $configPath) {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($json) { return @($json) }
    }
    return @()
}

function Save-AppList {
    param([array]$Apps)
    $Apps | ConvertTo-Json -Depth 2 | Set-Content $configPath -Encoding UTF8
}

# --- Credential helpers ---
function Get-StoredCredential {
    if (-not (Test-Path $keyPath) -or -not (Test-Path $credPath)) { return $null }
    try {
        $aesKey = [System.IO.File]::ReadAllBytes($keyPath)
        $lines  = Get-Content $credPath
        $user   = $lines[0]
        $pass   = ConvertTo-SecureString $lines[1] -Key $aesKey
        return New-Object PSCredential($user, $pass)
    } catch {
        return $null
    }
}

function Save-Credential {
    param([PSCredential]$Credential)
    if (-not (Test-Path $keyPath)) {
        $aesKey = New-Object byte[] 32
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($aesKey)
        [System.IO.File]::WriteAllBytes($keyPath, $aesKey)
    }
    $aesKey = [System.IO.File]::ReadAllBytes($keyPath)
    $encPass = ConvertFrom-SecureString -SecureString $Credential.Password -Key $aesKey
    @($Credential.UserName, $encPass) | Set-Content $credPath -Encoding UTF8
}

function Get-FileVersionString {
    param([string]$Path)
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        if ($vi.FileVersion) { return $vi.FileVersion }
        return 'N/A'
    } catch {
        return 'N/A'
    }
}

# --- Form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Elevated Launcher"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.ClientSize = New-Object System.Drawing.Size(700, 400)

# --- Credential status label ---
$lblCred = New-Object System.Windows.Forms.Label
$lblCred.Location = New-Object System.Drawing.Point(12, 12)
$lblCred.AutoSize = $true
$storedCred = Get-StoredCredential
if ($storedCred) {
    $lblCred.Text = "Credential: $($storedCred.UserName)"
    $lblCred.ForeColor = [System.Drawing.Color]::DarkGreen
} else {
    $lblCred.Text = "Credential: (none stored)"
    $lblCred.ForeColor = [System.Drawing.Color]::DarkRed
}
$form.Controls.Add($lblCred)

# --- ListView ---
$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.GridLines = $true
$lv.MultiSelect = $false
$lv.Location = New-Object System.Drawing.Point(12, 40)
$lv.Size = New-Object System.Drawing.Size(676, 300)
[void]$lv.Columns.Add('App Name', 180)
[void]$lv.Columns.Add('Version', 120)
[void]$lv.Columns.Add('Executable Path', 370)
$form.Controls.Add($lv)

# --- Populate ListView ---
function Update-ListView {
    $lv.Items.Clear()
    $apps = Get-AppList
    foreach ($app in $apps) {
        $version = Get-FileVersionString $app.Path
        $item = New-Object System.Windows.Forms.ListViewItem($app.Name)
        [void]$item.SubItems.Add($version)
        [void]$item.SubItems.Add($app.Path)
        [void]$lv.Items.Add($item)
    }
}
Update-ListView

# --- Buttons ---
$btnCred = New-Object System.Windows.Forms.Button
$btnCred.Text = "Store Credentials"
$btnCred.Location = New-Object System.Drawing.Point(12, 352)
$btnCred.Size = New-Object System.Drawing.Size(130, 30)
$form.Controls.Add($btnCred)

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = "Add App"
$btnAdd.Location = New-Object System.Drawing.Point(280, 352)
$btnAdd.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnAdd)

$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = "Remove App"
$btnRemove.Location = New-Object System.Drawing.Point(380, 352)
$btnRemove.Size = New-Object System.Drawing.Size(100, 30)
$form.Controls.Add($btnRemove)

$btnLaunch = New-Object System.Windows.Forms.Button
$btnLaunch.Text = "Launch"
$btnLaunch.Location = New-Object System.Drawing.Point(598, 352)
$btnLaunch.Size = New-Object System.Drawing.Size(90, 30)
$form.Controls.Add($btnLaunch)

# --- Store Credentials ---
$btnCred.Add_Click({
    $cred = Get-Credential -Message "Enter the credentials to use for launching applications."
    if ($cred) {
        Save-Credential -Credential $cred
        $lblCred.Text = "Credential: $($cred.UserName)"
        $lblCred.ForeColor = [System.Drawing.Color]::DarkGreen
    }
})

# --- Add App ---
$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Select an executable"
    $dlg.Filter = "Executables (*.exe;*.msi;*.cmd;*.bat)|*.exe;*.msi;*.cmd;*.bat|All files (*.*)|*.*"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $exePath = $dlg.FileName
    $defaultName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)

    $nameForm = New-Object System.Windows.Forms.Form
    $nameForm.Text = "App Name"
    $nameForm.StartPosition = "CenterParent"
    $nameForm.FormBorderStyle = "FixedDialog"
    $nameForm.MaximizeBox = $false
    $nameForm.MinimizeBox = $false
    $nameForm.ClientSize = New-Object System.Drawing.Size(350, 80)

    $lblN = New-Object System.Windows.Forms.Label
    $lblN.Text = "Display name:"
    $lblN.AutoSize = $true
    $lblN.Location = New-Object System.Drawing.Point(12, 14)
    $nameForm.Controls.Add($lblN)

    $txtN = New-Object System.Windows.Forms.TextBox
    $txtN.Text = $defaultName
    $txtN.Location = New-Object System.Drawing.Point(100, 12)
    $txtN.Size = New-Object System.Drawing.Size(235, 24)
    $nameForm.Controls.Add($txtN)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text = "OK"
    $btnOK.Location = New-Object System.Drawing.Point(245, 44)
    $btnOK.Size = New-Object System.Drawing.Size(90, 28)
    $btnOK.Add_Click({
        if (-not [string]::IsNullOrWhiteSpace($txtN.Text)) {
            $nameForm.DialogResult = [System.Windows.Forms.DialogResult]::OK
            $nameForm.Close()
        }
    })
    $nameForm.AcceptButton = $btnOK
    $nameForm.Controls.Add($btnOK)

    if ($nameForm.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $appName = $txtN.Text.Trim()
    $apps = @(Get-AppList)
    $apps += @{ Name = $appName; Path = $exePath }
    Save-AppList -Apps $apps
    Update-ListView
})

# --- Remove App ---
$btnRemove.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select an app to remove.", "Elevated Launcher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $idx = $lv.SelectedIndices[0]
    $apps = @(Get-AppList)
    $apps = @($apps | Where-Object { $apps.IndexOf($_) -ne $idx })
    Save-AppList -Apps $apps
    Update-ListView
})

# --- Launch ---
$btnLaunch.Add_Click({
    if ($lv.SelectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select an app to launch.", "Elevated Launcher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $exePath = $lv.SelectedItems[0].SubItems[2].Text

    if (-not (Test-Path $exePath)) {
        [System.Windows.Forms.MessageBox]::Show("Executable not found:`r`n$exePath", "Elevated Launcher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    $cred = Get-StoredCredential
    if (-not $cred) {
        [System.Windows.Forms.MessageBox]::Show("No credentials stored. Use 'Store Credentials' first.", "Elevated Launcher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    try {
        Start-Process -FilePath $exePath -Credential $cred -ErrorAction Stop
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to launch:`r`n$($_.Exception.Message)", "Elevated Launcher", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

[void]$form.ShowDialog()
