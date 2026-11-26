# Build AToolSlotLimit (UE4SS C++ mod) against the UE4SS.dll that is INSTALLED in the game, then install it.
# Why this way: the installed UE4SS is the community RevOG SB-UE4SS 1.3 build (Nexus; UE4SS.log: v3.0.1 Beta, Git SHA 08a0733, SHA-256 E0CC51CE...DABE) and
# Kaspersky blocks the Rust build scripts a full UE4SS build needs. So:
#   1. the import library is generated from the installed DLL's exports (every import is guaranteed to exist)
#   2. only dllmain.cpp is compiled, with the flags of a CMake-configured UE4SS tree (RE-UE4SS main @ 0196ef294,
#      2026-03-27, the closest public commit) in $Root
#   3. linked by hand with fmt (the only other dependency)
# One-time setup of $Root: clone RE-UE4SS at 0196ef294 (+ submodules) into $Root\RE-UE4SS, a CMakeLists.txt that does
# add_subdirectory(RE-UE4SS) + add_subdirectory(<this folder> AToolSlotLimit), then cmake -S . -B Output (CMake 3.29).
param([string]$Root = "D:\Modding\SBMods", [switch]$NoInstall)
$ErrorActionPreference = "Stop"
$cfg = (Get-Content "$PSScriptRoot\config.json" -Raw | ConvertFrom-Json)
$game = $cfg.sb_game + "\Binaries\Win64"
$vc = (Get-ChildItem "C:\Program Files\Microsoft Visual Studio\2022\*\VC\Tools\MSVC\*" -Directory | Select-Object -Last 1).FullName
$msb = (Get-ChildItem "C:\Program Files*\Microsoft Visual Studio\2022\*\MSBuild\Current\Bin\amd64\MSBuild.exe" | Select-Object -First 1).FullName
$sdk = (Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\Lib" -Directory | Sort-Object Name | Select-Object -Last 1).FullName
Set-Location $Root
# 1) import library from the installed UE4SS.dll
$ex = & "$vc\bin\Hostx64\x64\dumpbin.exe" /nologo /exports "$game\ue4ss\UE4SS.dll"
$names = $ex | Where-Object { $_ -match '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]{8}\s+(\S+)' } | ForEach-Object { $Matches[1] }
New-Item -ItemType Directory -Force implib, out | Out-Null
(@("LIBRARY UE4SS.dll", "EXPORTS") + ($names | ForEach-Object { "    $_" })) | Set-Content -Encoding ascii implib\UE4SS.def
& "$vc\bin\Hostx64\x64\lib.exe" /nologo /machine:x64 /def:implib\UE4SS.def /out:implib\UE4SS.lib | Out-Null
# 2) compile our source + fmt
& $msb Output\AToolSlotLimit\AToolSlotLimit.vcxproj /nologo /v:m /t:ClCompile /p:Configuration=Game__Shipping__Win64 /p:Platform=x64 /p:BuildProjectReferences=false
if ($LASTEXITCODE -ne 0) { throw "compile failed" }
& $msb Output\_deps\fmt-build\fmt.vcxproj /nologo /v:m /p:Configuration=Game__Shipping__Win64 /p:Platform=x64
# 3) link
& "$vc\bin\Hostx64\x64\link.exe" /nologo /DLL /OUT:out\main.dll /MACHINE:X64 "/LIBPATH:$vc\lib\x64" "/LIBPATH:$sdk\um\x64" "/LIBPATH:$sdk\ucrt\x64" `
    Output\AToolSlotLimit\AToolSlotLimit.dir\Game__Shipping__Win64\dllmain.obj implib\UE4SS.lib Output\Game__Shipping__Win64\lib\fmt.lib kernel32.lib user32.lib
if ($LASTEXITCODE -ne 0) { throw "link failed" }
if (-not $NoInstall) {
    $d = "$game\ue4ss\Mods\AToolSlotLimit"
    New-Item -ItemType Directory -Force "$d\dlls" | Out-Null
    Copy-Item out\main.dll "$d\dlls\main.dll" -Force
    if (-not (Test-Path "$d\enabled.txt")) { Set-Content "$d\enabled.txt" "1" }
    "installed -> $d"
}
