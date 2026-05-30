<#
.SYNOPSIS
    Reads the BundleId GUID from a WiX Burn bundle's .wixburn PE section.

.DESCRIPTION
    WiX Burn (v3+) places a BURN_SECTION header at the start of the
    .wixburn section inside the bundle's PE executable. Layout:

        magic    : DWORD = 0x00f14300
        version  : DWORD
        bundleId : GUID (16 bytes)
        ...

    The bundle's ARP key under
    HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\ (or HKCU
    for per-user bundles) is named with this GUID. Reference:
    https://github.com/wixtoolset/wix (src/burn, section.h, BURN_SECTION).

    Native code only:
      - System.IO.File / BinaryReader  (.NET BCL)
      - PE COFF / section table parsing in PowerShell
    No third-party modules, no vendored binaries, no external tools.

.PARAMETER Path
    Path to a WiX Burn bundle .exe.

.EXAMPLE
    .\Get-WixBurnMetadata.ps1 -Path .\ContosoBundle.exe
#>
param([Parameter(Mandatory)][string]$Path)

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
}

$stream = $null
try {
    $stream = [System.IO.File]::OpenRead((Resolve-Path -LiteralPath $Path))
    $br = New-Object System.IO.BinaryReader($stream)

    # DOS header -> e_lfanew at 0x3C
    [void]$stream.Seek(0x3C, 'Begin')
    $peOffset = $br.ReadUInt32()
    if ($peOffset -le 0 -or $peOffset -gt ($stream.Length - 24)) { return $null }

    # PE signature
    [void]$stream.Seek($peOffset, 'Begin')
    if ($br.ReadUInt32() -ne 0x00004550) { return $null }

    # COFF header
    [void]$br.ReadUInt16()                # Machine
    $numSections = $br.ReadUInt16()
    [void]$br.ReadUInt32()                # TimeDateStamp
    [void]$br.ReadUInt32()                # PointerToSymbolTable
    [void]$br.ReadUInt32()                # NumberOfSymbols
    $sizeOfOpt = $br.ReadUInt16()
    [void]$br.ReadUInt16()                # Characteristics

    if ($numSections -le 0 -or $numSections -gt 128) { return $null }

    # Skip optional header to reach section table
    [void]$stream.Seek($sizeOfOpt, 'Current')

    $burnOffset = 0
    for ($i = 0; $i -lt $numSections; $i++) {
        $name = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(8)).TrimEnd([char]0)
        [void]$br.ReadUInt32()            # VirtualSize
        [void]$br.ReadUInt32()            # VirtualAddress
        [void]$br.ReadUInt32()            # SizeOfRawData
        $rawPtr = $br.ReadUInt32()
        [void]$br.ReadUInt32()            # PointerToRelocations
        [void]$br.ReadUInt32()            # PointerToLinenumbers
        [void]$br.ReadUInt16()            # NumberOfRelocations
        [void]$br.ReadUInt16()            # NumberOfLinenumbers
        [void]$br.ReadUInt32()            # Characteristics
        if ($name -eq '.wixburn') { $burnOffset = $rawPtr; break }
    }

    if ($burnOffset -eq 0) { return $null }

    # BURN_SECTION: magic(4), version(4), guidBundleId(16)
    [void]$stream.Seek($burnOffset, 'Begin')
    if ($br.ReadUInt32() -ne 0x00f14300) { return $null }
    $burnVersion = $br.ReadUInt32()
    $guidBytes   = $br.ReadBytes(16)
    $bundleId    = (New-Object Guid (,$guidBytes)).ToString('B').ToUpper()

    [PSCustomObject]@{
        IsWixBurnBundle = $true
        BurnVersion     = $burnVersion
        BundleId        = $bundleId
        ArpKeyHKLM      = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$bundleId"
        ArpKeyHKCU      = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$bundleId"
    }
} finally {
    if ($stream) { $stream.Dispose() }
}
