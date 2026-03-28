# Generates AES-encrypted credential files for use during OSD.
# Run this once on any admin workstation, then copy the 3 output files
# alongside OSD-ComputerSetup.ps1 in the MECM package.
#
# Output files:
#   mecm.key  - 256-bit AES key
#   mecm.user - plaintext username (DOMAIN\user)
#   mecm.pass - AES-encrypted password

param(
    [string]$OutputPath = $PSScriptRoot
)

$username = Read-Host -Prompt 'Enter the service account username (DOMAIN\user)'
$securePass = Read-Host -Prompt 'Enter the password' -AsSecureString

# Generate a random 256-bit AES key
$aesKey = New-Object byte[] 32
[System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($aesKey)

# Encrypt the password with the AES key (machine-portable, no DPAPI)
$encryptedPass = ConvertFrom-SecureString -SecureString $securePass -Key $aesKey

# Write files
$keyPath  = Join-Path $OutputPath 'mecm.key'
$userPath = Join-Path $OutputPath 'mecm.user'
$passPath = Join-Path $OutputPath 'mecm.pass'

[System.IO.File]::WriteAllBytes($keyPath, $aesKey)
Set-Content -Path $userPath -Value $username -Encoding ASCII -NoNewline
Set-Content -Path $passPath -Value $encryptedPass -Encoding ASCII -NoNewline

Write-Host "Credential files written to $OutputPath" -ForegroundColor Green
Write-Host "  $keyPath"
Write-Host "  $userPath"
Write-Host "  $passPath"
Write-Host ''
Write-Host 'Place these files alongside OSD-ComputerSetup.ps1 in the MECM package.' -ForegroundColor Yellow
