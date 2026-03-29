<#
.SYNOPSIS
    Converts an image file (SVG, PNG, BMP, JPG) to a multi-size .ico file.

.DESCRIPTION
    Generates a standard Windows .ico containing 16x16, 32x32, 48x48, and
    256x256 PNG entries from any common image format. Supports both command-line
    and drag-and-drop GUI modes.

    CLI:   .\ConvertTo-Icon.ps1 -FileIn "icon.png" -FileOut "icon.ico"
    GUI:   .\ConvertTo-Icon.ps1   (no parameters — opens drop target window)

.PARAMETER FileIn
    Path to the source image (PNG, JPG, BMP, or SVG).

.PARAMETER FileOut
    Path for the output .ico file. Defaults to the input path with .ico extension.

.EXAMPLE
    .\ConvertTo-Icon.ps1 -FileIn C:\art\logo.png -FileOut C:\art\logo.ico

.EXAMPLE
    .\ConvertTo-Icon.ps1
    Opens a drag-and-drop GUI window.
#>
param(
    [string]$FileIn,
    [string]$FileOut
)

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$script:IcoSizes = @(256, 48, 32, 16)

function Convert-ImageToIcon {
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    if (-not (Test-Path $SourcePath)) {
        throw "File not found: $SourcePath"
    }

    $ext = [System.IO.Path]::GetExtension($SourcePath).ToLower()
    if ($ext -eq '.svg') {
        throw "SVG support requires rsvg-convert or Inkscape on PATH. Convert to PNG first, or install one of these tools."
    }

    $srcImage = [System.Drawing.Image]::FromFile((Resolve-Path $SourcePath).Path)

    try {
        $pngStreams = @()

        foreach ($size in $script:IcoSizes) {
            $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality

            # Scale preserving aspect ratio, center on transparent background
            $srcRatio = $srcImage.Width / $srcImage.Height
            if ($srcRatio -gt 1) {
                $drawW = $size
                $drawH = [int]($size / $srcRatio)
                $drawX = 0
                $drawY = [int](($size - $drawH) / 2)
            } else {
                $drawH = $size
                $drawW = [int]($size * $srcRatio)
                $drawX = [int](($size - $drawW) / 2)
                $drawY = 0
            }

            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($srcImage, $drawX, $drawY, $drawW, $drawH)
            $g.Dispose()

            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $pngStreams += @{ Size = $size; Data = $ms.ToArray() }
            $ms.Dispose()
            $bmp.Dispose()
        }

        # Write ICO file
        # Header: 2 reserved + 2 type (1=icon) + 2 count
        # Directory: 16 bytes per entry
        # Data: PNG blobs
        $fs = [System.IO.File]::Create($OutputPath)
        $bw = New-Object System.IO.BinaryWriter($fs)

        # Header
        $bw.Write([uint16]0)                        # Reserved
        $bw.Write([uint16]1)                        # Type: 1 = ICO
        $bw.Write([uint16]$pngStreams.Count)         # Number of images

        # Calculate data offset: header(6) + directory(16 * count)
        $dataOffset = 6 + (16 * $pngStreams.Count)

        # Directory entries
        foreach ($entry in $pngStreams) {
            $dimByte = if ($entry.Size -ge 256) { 0 } else { [byte]$entry.Size }
            $bw.Write([byte]$dimByte)               # Width (0 = 256)
            $bw.Write([byte]$dimByte)               # Height (0 = 256)
            $bw.Write([byte]0)                      # Color palette count
            $bw.Write([byte]0)                      # Reserved
            $bw.Write([uint16]1)                    # Color planes
            $bw.Write([uint16]32)                   # Bits per pixel
            $bw.Write([uint32]$entry.Data.Length)    # Data size
            $bw.Write([uint32]$dataOffset)           # Data offset
            $dataOffset += $entry.Data.Length
        }

        # Image data
        foreach ($entry in $pngStreams) {
            $bw.Write($entry.Data)
        }

        $bw.Close()
        $fs.Close()

        return $OutputPath
    }
    finally {
        $srcImage.Dispose()
    }
}

# ---------------------------------------------------------------------------
# CLI mode
# ---------------------------------------------------------------------------

if ($FileIn) {
    if (-not $FileOut) {
        $FileOut = [System.IO.Path]::ChangeExtension($FileIn, '.ico')
    }

    try {
        $result = Convert-ImageToIcon -SourcePath $FileIn -OutputPath $FileOut
        Write-Host "Created: $result" -ForegroundColor Green
        Write-Host "  Sizes: $($script:IcoSizes -join ', ')px"
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
    exit 0
}

# ---------------------------------------------------------------------------
# GUI mode (no parameters)
# ---------------------------------------------------------------------------

$form = New-Object System.Windows.Forms.Form
$form.Text = "ConvertTo-Icon"
$form.Size = New-Object System.Drawing.Size(420, 300)
$form.MinimumSize = $form.Size
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 220)
$form.AllowDrop = $true

$lblDrop = New-Object System.Windows.Forms.Label
$lblDrop.Text = "Drop Image Here`n`nPNG  JPG  BMP  SVG"
$lblDrop.Dock = [System.Windows.Forms.DockStyle]::Fill
$lblDrop.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblDrop.Font = New-Object System.Drawing.Font("Segoe UI", 14)
$lblDrop.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
$lblDrop.AllowDrop = $true
$form.Controls.Add($lblDrop)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Dock = [System.Windows.Forms.DockStyle]::Bottom
$lblStatus.Height = 32
$lblStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
$lblStatus.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 40)
$form.Controls.Add($lblStatus)

$dragHandler = {
    $e = $args[1]
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        $ext = [System.IO.Path]::GetExtension($files[0]).ToLower()
        if ($ext -in @('.png', '.jpg', '.jpeg', '.bmp', '.svg')) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        } else {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::None
        }
    }
}

$dropHandler = {
    $e = $args[1]
    $files = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    $inputFile = $files[0]
    $outputFile = [System.IO.Path]::ChangeExtension($inputFile, '.ico')

    $lblDrop.ForeColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
    $lblDrop.Text = "Converting..."
    $lblStatus.Text = ""
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $result = Convert-ImageToIcon -SourcePath $inputFile -OutputPath $outputFile
        $lblDrop.ForeColor = [System.Drawing.Color]::FromArgb(80, 200, 80)
        $lblDrop.Text = "Done"
        $lblStatus.Text = $result
    }
    catch {
        $lblDrop.ForeColor = [System.Drawing.Color]::FromArgb(255, 100, 100)
        $lblDrop.Text = "Error"
        $lblStatus.Text = $_.Exception.Message
    }

    # Reset after 3 seconds
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 3000
    $timer.Add_Tick({
        $lblDrop.ForeColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
        $lblDrop.Text = "Drop Image Here`n`nPNG  JPG  BMP  SVG"
        $timer.Stop()
        $timer.Dispose()
    })
    $timer.Start()
}

$form.Add_DragEnter($dragHandler)
$form.Add_DragDrop($dropHandler)
$lblDrop.Add_DragEnter($dragHandler)
$lblDrop.Add_DragDrop($dropHandler)

[void]$form.ShowDialog()
