# Filesystem

Tools for files and file names.

## Contents

| File | Purpose |
|------|---------|
| `ConvertTo-Icon.ps1` | Converts a PNG, JPG, BMP or SVG image to a multi-size `.ico` file (256, 48, 32 and 16 pixels). Has a command-line mode (`-FileIn`, `-FileOut`) and a drag-and-drop window. SVG input needs `rsvg-convert` or Inkscape on the PATH. Without them, convert the SVG to PNG first. |
| `rename-extensions.ps1` | Renames file extensions for a safe transfer (for example `.ps1` to `.notps1`). `-Undo` restores the names. `-Archive` zips the result. |

## Requirements

PowerShell 5.1 or later.
