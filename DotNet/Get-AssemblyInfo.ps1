<#
.SYNOPSIS
    Inspects a .NET assembly via reflection, listing types, properties, methods, and attributes.

.DESCRIPTION
    Loads a .NET DLL and enumerates all public types with their declared
    properties, methods (excluding property accessors), and custom attributes.
    Useful for reverse-engineering or documenting assemblies without source code.

.PARAMETER Path
    Path to the .NET DLL to inspect.

.EXAMPLE
    .\Get-AssemblyInfo.ps1 -Path C:\lib\MyLibrary.dll
#>
param(
    [Parameter(Mandatory)]
    [string]$Path
)

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

$asm = [System.Reflection.Assembly]::LoadFrom((Resolve-Path $Path).Path)

Write-Host "=== $($asm.GetName().Name) v$($asm.GetName().Version) ===" -ForegroundColor Cyan

foreach ($type in ($asm.GetTypes() | Sort-Object FullName)) {
    Write-Host "`n--- $($type.FullName) ---" -ForegroundColor Yellow
    Write-Host "  Base: $($type.BaseType)"

    $props = $type.GetProperties(
        [System.Reflection.BindingFlags]::Public -bor
        [System.Reflection.BindingFlags]::Instance -bor
        [System.Reflection.BindingFlags]::DeclaredOnly
    )
    if ($props.Count -gt 0) {
        Write-Host "  Properties:" -ForegroundColor Gray
        foreach ($p in $props) {
            Write-Host "    $($p.PropertyType.Name) $($p.Name)"
        }
    }

    $methods = $type.GetMethods(
        [System.Reflection.BindingFlags]::Public -bor
        [System.Reflection.BindingFlags]::Instance -bor
        [System.Reflection.BindingFlags]::DeclaredOnly
    ) | Where-Object { -not $_.IsSpecialName }
    if ($methods.Count -gt 0) {
        Write-Host "  Methods:" -ForegroundColor Gray
        foreach ($m in $methods) {
            $params = ($m.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', '
            Write-Host "    $($m.ReturnType.Name) $($m.Name)($params)"
        }
    }

    $attrs = $type.GetCustomAttributes($true)
    if ($attrs.Count -gt 0) {
        Write-Host "  Attributes:" -ForegroundColor Gray
        foreach ($a in $attrs) {
            Write-Host "    [$($a.GetType().Name)]"
        }
    }
}
