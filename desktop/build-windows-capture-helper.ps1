param([Parameter(Mandatory=$true)][ValidateSet('x64','arm64')][string]$Arch,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = & $vswhere -latest -products '*' -property installationPath
if (!$installation) { throw 'Visual Studio C++ build tools are required on the Windows Runner.' }
$vcvars = Join-Path $installation 'VC/Auxiliary/Build/vcvarsall.bat'
if (!(Test-Path $vcvars)) { throw 'Visual Studio C++ environment was not found.' }
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$source = Join-Path $PSScriptRoot 'native/windows-window-bounds.cpp'
$binary = Join-Path $OutputDirectory 'synca-window-bounds.exe'
$object = Join-Path $OutputDirectory 'window-bounds.obj'
$target = if ($Arch -eq 'arm64') { 'amd64_arm64' } else { 'amd64' }
$command = 'call "'+$vcvars+'" '+$target+' >nul && cl.exe /nologo /O2 /MT /W4 /WX /EHsc /std:c++17 /D_WIN32_WINNT=0x0A00 "'+$source+'" /Fe:"'+$binary+'" /Fo:"'+$object+'" /link user32.lib dwmapi.lib'
& $env:ComSpec /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw "Windows capture helper build failed: $LASTEXITCODE" }
Remove-Item -LiteralPath $object -Force
