# OSD-ComputerSetup.ps1
# WinPE prestart command -- collects computer role (OU) and hostname from the
# imaging technician BEFORE the task sequence is selected. No ServiceUI required.
#
# Inspired by PSAppDeployToolkit v4.1 (https://github.com/psappdeploytoolkit/psappdeploytoolkit)
# which demonstrated that ServiceUI.exe token manipulation is a security risk.
# In WinPE, the prestart command mechanism provides native user interaction
# without session-bridging or MDT dependencies.
#
# Sets these task sequence variables:
#   OSDComputerName  - sanitized hostname (uppercase, alphanumeric, max 8 chars)
#   OSDDomainOUName  - LDAP path to the target OU
#   OSDComputerRole  - friendly role name (e.g., "Legal Desktop")
#   OSDAppProfile    - app install profile tied to the role (for Install Application steps)
#
# Configuration:
#   role-map.json    - maps role display names to OU paths and app profiles
#   mecm.key/user/pass - encrypted credentials for MECM hostname lookup (optional)
#
# Prestart command line (set on boot media Customization tab):
#   cmd /C OSD-ComputerSetup.bat
#
# Hostname rules:
#   - Alphanumeric only (A-Z, 0-9)
#   - Forced uppercase
#   - Exactly 8 characters
#   - No spaces, special characters, BOMs, or NBSP
#
# Exit codes:
#   0    - success, variables set
#   1630 - user cancelled, halts task sequence

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- TS Environment ---
try {
    $tsenv = New-Object -COMObject Microsoft.SMS.TSEnvironment
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Failed to connect to the task sequence environment.`r`n`r`n$($_.Exception.Message)",
        "Computer Setup",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# --- Load role map ---
$roleMapPath = Join-Path $PSScriptRoot 'role-map.json'
if (-not (Test-Path $roleMapPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "role-map.json not found at:`r`n$roleMapPath",
        "Computer Setup",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

$roleConfig = Get-Content $roleMapPath -Raw | ConvertFrom-Json
if (-not $roleConfig.Roles -or $roleConfig.Roles.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show(
        "role-map.json contains no roles.",
        "Computer Setup",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# --- MECM site config (for hostname duplicate check) ---
$siteServer = 'sccm01.contoso.com'
$siteCode   = 'MCM'

# --- Build credential from encrypted files (optional) ---
$keyFile  = Join-Path $PSScriptRoot 'mecm.key'
$userFile = Join-Path $PSScriptRoot 'mecm.user'
$passFile = Join-Path $PSScriptRoot 'mecm.pass'

$naaCred = $null
if ((Test-Path $keyFile) -and (Test-Path $userFile) -and (Test-Path $passFile)) {
    try {
        $aesKey     = [System.IO.File]::ReadAllBytes($keyFile)
        $naaUser    = (Get-Content $userFile -Raw).Trim()
        $securePass = ConvertTo-SecureString (Get-Content $passFile -Raw).Trim() -Key $aesKey
        $naaCred    = New-Object PSCredential($naaUser, $securePass)
    } catch {
        # Credentials failed to load -- duplicate check will be skipped or prompt
    }
}

# --- Build form ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "Computer Setup"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true
$form.ClientSize = New-Object System.Drawing.Size(420, 230)
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

# --- Role label ---
$lblRole = New-Object System.Windows.Forms.Label
$lblRole.Text = "Computer role:"
$lblRole.AutoSize = $true
$lblRole.Location = New-Object System.Drawing.Point(12, 15)
$form.Controls.Add($lblRole)

# --- Role ComboBox (shows friendly names only) ---
$cboRole = New-Object System.Windows.Forms.ComboBox
$cboRole.DropDownStyle = "DropDownList"
$cboRole.Location = New-Object System.Drawing.Point(12, 38)
$cboRole.Size = New-Object System.Drawing.Size(390, 24)
foreach ($role in $roleConfig.Roles) {
    [void]$cboRole.Items.Add($role.Name)
}
$cboRole.SelectedIndex = 0
$form.Controls.Add($cboRole)

# --- Hostname label ---
$lblName = New-Object System.Windows.Forms.Label
$lblName.Text = "Computer name (8 characters, alphanumeric only):"
$lblName.AutoSize = $true
$lblName.Location = New-Object System.Drawing.Point(12, 78)
$form.Controls.Add($lblName)

# --- Hostname TextBox (sanitized input) ---
$txtName = New-Object System.Windows.Forms.TextBox
$txtName.Location = New-Object System.Drawing.Point(12, 101)
$txtName.Size = New-Object System.Drawing.Size(390, 24)
$txtName.MaxLength = 8
$txtName.CharacterCasing = "Upper"

# Block non-alphanumeric input at the keypress level
$txtName.Add_KeyPress({
    param($s, $e)
    if (-not [char]::IsLetterOrDigit($e.KeyChar) -and -not [char]::IsControl($e.KeyChar)) {
        $e.Handled = $true
    }
})

# Strip anything that slips through (paste, IME) on text change
$txtName.Add_TextChanged({
    $clean = ($txtName.Text -replace '[^A-Za-z0-9]', '').ToUpper()
    if ($clean -ne $txtName.Text) {
        $pos = $txtName.SelectionStart
        $txtName.Text = $clean
        $txtName.SelectionStart = [Math]::Min($pos, $clean.Length)
    }
    $btnOK.Enabled = ($clean.Length -eq 8)
})
$form.Controls.Add($txtName)

# --- Status label (for validation feedback) ---
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(12, 132)
$lblStatus.ForeColor = [System.Drawing.Color]::Red
$form.Controls.Add($lblStatus)

# --- OK Button ---
$btnOK = New-Object System.Windows.Forms.Button
$btnOK.Text = "OK"
$btnOK.Location = New-Object System.Drawing.Point(220, 180)
$btnOK.Size = New-Object System.Drawing.Size(88, 32)
$btnOK.Enabled = $false
$form.AcceptButton = $btnOK
$form.Controls.Add($btnOK)

# --- Cancel Button ---
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Cancel"
$btnCancel.Location = New-Object System.Drawing.Point(314, 180)
$btnCancel.Size = New-Object System.Drawing.Size(88, 32)
$form.CancelButton = $btnCancel
$form.Controls.Add($btnCancel)

# --- OK handler ---
$btnOK.Add_Click({
    $roleName    = [string]$cboRole.SelectedItem
    $computerName = $txtName.Text.Trim()

    if ([string]::IsNullOrWhiteSpace($roleName)) {
        $lblStatus.Text = "Select a role."
        return
    }

    # Find the selected role in the config
    $selectedRole = $roleConfig.Roles | Where-Object { $_.Name -eq $roleName }
    if (-not $selectedRole) {
        $lblStatus.Text = "Role not found in configuration."
        return
    }

    # --- Check MECM for duplicate hostname ---
    $lblStatus.ForeColor = [System.Drawing.Color]::DarkBlue
    $lblStatus.Text = "Checking hostname availability..."
    $form.Refresh()

    try {
        $cimParams = @{
            Namespace    = "root\sms\site_$siteCode"
            ComputerName = $siteServer
            Query        = "SELECT Name FROM SMS_R_System WHERE Name = '$computerName'"
            ErrorAction  = 'Stop'
        }
        if ($naaCred) { $cimParams.Credential = $naaCred }

        $existing = Get-CimInstance @cimParams

        if ($existing) {
            $lblStatus.ForeColor = [System.Drawing.Color]::Red
            $lblStatus.Text = "'$computerName' already exists in MECM. Delete it first."
            return
        }
    } catch {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Cannot verify hostname against MECM:`r`n$($_.Exception.Message)`r`n`r`nContinue anyway?",
            "Computer Setup",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
            $lblStatus.ForeColor = [System.Drawing.Color]::Red
            $lblStatus.Text = "Hostname check cancelled."
            return
        }
    }

    # --- Set TS Variables ---
    $tsenv.Value("OSDComputerName") = $computerName
    $tsenv.Value("OSDDomainOUName") = $selectedRole.OUPath
    $tsenv.Value("OSDComputerRole") = $selectedRole.Name
    $tsenv.Value("OSDAppProfile")   = $selectedRole.AppProfile

    $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $form.Close()
})

# --- Cancel handler ---
$btnCancel.Add_Click({
    $form.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Close()
})

# --- Show ---
$result = $form.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    exit 1630
}

exit 0
