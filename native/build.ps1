[CmdletBinding()]
param(
    [string]$SdkPath,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $SdkPath) {
    $SdkPath = Join-Path $scriptRoot 'deps\RED4ext.SDK'
}
if (-not $OutputPath) {
    $OutputPath = Join-Path $scriptRoot 'build'
}

if (-not (Test-Path -LiteralPath (Join-Path $SdkPath 'include\RED4ext\RED4ext.hpp'))) {
    throw "RED4ext.SDK headers not found at $SdkPath"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vsDevCmd = $null
if (Test-Path -LiteralPath $vswhere) {
    $installationPath = & $vswhere -latest -prerelease -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath
    if ($LASTEXITCODE -eq 0 -and $installationPath) {
        $candidate = Join-Path $installationPath 'Common7\Tools\VsDevCmd.bat'
        if (Test-Path -LiteralPath $candidate) {
            $vsDevCmd = $candidate
        }
    }
}

if (-not $vsDevCmd) {
    $fallbacks = @(
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat',
        'C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\Tools\VsDevCmd.bat'
    )
    $vsDevCmd = $fallbacks | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if (-not $vsDevCmd) {
    throw 'Visual Studio C++ developer environment not found.'
}

New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

$include = Join-Path $SdkPath 'include'
$vendor = Join-Path $SdkPath 'vendor\D3D12MemAlloc'
$source = Join-Path $PSScriptRoot 'src\BlackPillarsRemover.cpp'
$object = Join-Path $OutputPath 'BlackPillarsRemover.obj'
$dll = Join-Path $OutputPath 'BlackPillarsRemover.dll'
$importLibrary = Join-Path $OutputPath 'BlackPillarsRemover.lib'

$compileCommand = @(
    'call', ('"{0}"' -f $vsDevCmd), '-arch=x64', '-host_arch=x64', '&&',
    'cl.exe', '/nologo', '/std:c++20', '/EHsc', '/O2', '/MD', '/LD',
    '/W4', '/DWIN32_LEAN_AND_MEAN',
    ('/I"{0}"' -f $include),
    ('/I"{0}"' -f $vendor),
    ('/Fo:"{0}"' -f $object),
    ('"{0}"' -f $source),
    '/link', 'user32.lib',
    ('/OUT:"{0}"' -f $dll),
    ('/IMPLIB:"{0}"' -f $importLibrary)
) -join ' '

& $env:ComSpec /d /s /c $compileCommand
if ($LASTEXITCODE -ne 0) {
    throw "Native build failed with exit code $LASTEXITCODE"
}

Write-Host "Built $dll"
