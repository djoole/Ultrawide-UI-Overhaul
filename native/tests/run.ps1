$ErrorActionPreference = 'Stop'
$nativeRoot = Split-Path -Parent $PSScriptRoot
$build = Join-Path $nativeRoot 'build-boundary-tests'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
$dev = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
function Invoke-NativeTestCommand([string]$Command) {
    & $env:ComSpec /d /s /c ('call "{0}" -arch=x64 -host_arch=x64 >nul && {1}' -f $dev, $Command)
    if ($LASTEXITCODE -ne 0) { throw "Native test command failed ($LASTEXITCODE)" }
}
$boundary = Join-Path $build 'boundary.obj'
$probe = Join-Path $build 'probe.obj'
Invoke-NativeTestCommand ('ml64 /nologo /c /Fo"{0}" "{1}"' -f $boundary, (Join-Path $nativeRoot 'src\FitReferenceRectBoundary.asm'))
Invoke-NativeTestCommand ('ml64 /nologo /c /DUWUI_BOUNDARY_CONTRACT_TEST /Fo"{0}" "{1}"' -f $probe, (Join-Path $PSScriptRoot 'BoundaryProbe.asm'))
Invoke-NativeTestCommand ('cl /nologo /std:c++20 /O2 /EHsc /W4 /Fo"{0}\contract.obj" /Fe"{0}\contract.exe" "{1}" "{2}" "{3}"' -f $build, (Join-Path $PSScriptRoot 'BoundaryHarness.cpp'), $boundary, $probe)
& (Join-Path $build 'contract.exe')
if ($LASTEXITCODE -ne 0) { throw 'Register-preservation contract failed' }
Invoke-NativeTestCommand ('ml64 /nologo /c /Fo"{0}" "{1}"' -f $probe, (Join-Path $PSScriptRoot 'BoundaryProbe.asm'))
Invoke-NativeTestCommand ('cl /nologo /std:c++20 /O2 /EHsc /W4 /DWIN32_LEAN_AND_MEAN /I"{0}\deps\RED4ext.SDK\include" /I"{0}\deps\RED4ext.SDK\vendor\D3D12MemAlloc" /Fo"{1}\geometry.obj" /Fe"{1}\geometry.exe" "{2}" "{3}" "{4}" /link user32.lib' -f $nativeRoot, $build, (Join-Path $PSScriptRoot 'GeometryHarness.cpp'), $boundary, $probe)
& (Join-Path $build 'geometry.exe')
if ($LASTEXITCODE -ne 0) { throw 'Production geometry tests failed' }
