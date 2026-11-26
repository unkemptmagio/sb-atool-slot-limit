# Build AToolSlotLimit for the Chrisr0/RE-UE4SS 3.1.0-x line (the UE4SS PEFA's readme lists). Same trick as build.ps1: compile only dllmain.cpp
# against that tree's headers and link against an import library generated from ITS UE4SS.dll, so every import is guaranteed to exist there.
# Why a second build: the DLL links to C++ symbols of the host UE4SS (CppUserModBase virtuals); the two lines have different signatures.
# One-time setup under $Root (default D:\Modding\SBMods-chrisr0), nothing here touches the game folder:
#   git clone --depth 1 --branch 3.1.0-5 https://github.com/Chrisr0/RE-UE4SS.git $Root\RE-UE4SS
#   git -C $Root\RE-UE4SS submodule update --init --depth 1 deps/first/Unreal          (headers only; the Rust submodule is not needed)
#   git clone --depth 1 --branch 10.2.1 https://github.com/fmtlib/fmt.git $Root\deps\fmt   (Chrisr0's tree pins fmt 10.2.1; fmt 11 breaks its Output.hpp)
#   UE4SS_v3.1.0-5.zip from github.com/Chrisr0/RE-UE4SS/releases, extracted; pass its UE4SS.dll as -Ue4ssDll
# The remaining header-only dependencies (glaze, zydis, polyhook2, imgui, ...) are taken from -Deps (a CMake configure of upstream RE-UE4SS).
param([Parameter(Mandatory)][string]$Ue4ssDll, [string]$Root = "D:\Modding\SBMods-chrisr0", [string]$Deps = "D:\Modding\SBMods\Output\_deps", [switch]$AllowAnyUe4ss)
$ErrorActionPreference = "Stop"
$tree = "$Root\RE-UE4SS"; $work = "$Root\build"
foreach ($p in "$tree\UE4SS\include", "$tree\deps\first\Unreal\include", "$Root\deps\fmt\include", $Deps, $Ue4ssDll) { if (-not (Test-Path -LiteralPath $p)) { throw "missing: $p (see the setup notes at the top of this script)" } }
$vcvars = Get-ChildItem "C:\Program Files*\Microsoft Visual Studio\2022\*\VC\Auxiliary\Build\vcvars64.bat" | Select-Object -First 1 -ExpandProperty FullName
if (-not $vcvars) { throw "Visual Studio 2022 C++ build tools not found" }
New-Item -ItemType Directory -Force $work | Out-Null
Remove-Item -LiteralPath "$work\main.dll", "$work\imports.txt", "$work\dllmain.obj", "$work\exports.txt" -ErrorAction SilentlyContinue   # never leave a stale result from an earlier run
$inc = "UE4SS\include","UE4SS\generated_include","deps\first\File\include","deps\first\Helpers\include","deps\first\String\include","deps\first\DynamicOutput\include","deps\first\Unreal\include","deps\first\Unreal\generated_include","deps\first\Unreal\include\Unreal","deps\first\Unreal\include\Unreal\Core","deps\first\SinglePassSigScanner\include","deps\first\Constructs\include","deps\first\Function\include","deps\first\ASMHelper\include","deps\first\LuaMadeSimple\include","deps\first\LuaRaw\include","deps\first\IniParser\include","deps\first\ParserBase\include","deps\first\JSON\include","deps\first\Input\include","deps\first\MProgram\include","deps\first\ScopedTimer\include","deps\first\Profiler\include" | ForEach-Object { "/I`"$tree\$_`"" }
$ext = @("$Root\deps\fmt\include") + ("glaze-src\include","polyhook2-src","zydis-src\include","zydis-build","zydis-src\src","zydis-src\dependencies\zycore\include","zydis-build\zycore","polyhook2-src\asmtk\src","polyhook2-src\asmjit\src","imgui-src","imguitextedit-src","iconfontcppheaders-src","glfw-src\include" | ForEach-Object { "$Deps\$_" }) + @("$tree\deps\third\glad\include") | ForEach-Object { "/external:I`"$_`"" }
$defs = "WIN32","_WINDOWS","_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR","NDEBUG","ASMTK_STATIC","ASMJIT_STATIC","UE4SS_LIB_VERSION_MAJOR=3","UE4SS_LIB_VERSION_MINOR=1","UE4SS_LIB_VERSION_HOTFIX=0","UE4SS_LIB_VERSION_PRERELEASE=0","UE4SS_LIB_VERSION_BETA=0","UE4SS_LIB_BETA_STARTED=1","UE4SS_LIB_IS_BETA=0","UE4SS_LIB_BUILD_GITSHA=\`"d3d10044\`"","UE4SS_CONFIGURATION=\`"Game__Shipping__Win64\`"","HAS_INPUT","_UNICODE","UNICODE","_WIN32_WINNT=0x0A00","WINVER=0x0A00","UE_GAME","UE_BUILD_SHIPPING","PLATFORM_WINDOWS","PLATFORM_MICROSOFT","OVERRIDE_PLATFORM_HEADER_NAME=Windows","UBT_COMPILED_PLATFORM=Win64","RC_STRING_BUILD_STATIC","ZYDIS_STATIC_BUILD","ZYCORE_STATIC_BUILD","RC_LUA_RAW_BUILD_STATIC","DISABLE_PROFILER","IS_TRACY=0","IS_SUPERLUMINAL=0","IMGUI_IMPL_WIN32_DISABLE_GAMEPAD","AToolSlotLimit_EXPORTS" | ForEach-Object { "/D$_" }
$ver = (Get-FileHash -LiteralPath $Ue4ssDll -Algorithm SHA256).Hash
$allowed = "2E7B3E7E8760263B99AD45FD3EE3C35930E43D8C38D15B7E41685E8A3C26E2C4", "458839B77D05255F228045210270B01597D47FC83004CD47937126B2409A26EE", "F3F0229E8D046824C6D71DB256F1C9BBBDA9652A193643C28FA4E6C329E17670"   # Chrisr0 3.1.0-4 / -5 / -6
if ($ver -notin $allowed -and -not $AllowAnyUe4ss) { throw "UE4SS.dll $ver is not a known Chrisr0 3.1.0 build (-4/-5/-6). This DLL is built for that line only; pass -AllowAnyUe4ss to override." }
@"
@echo off
call "$vcvars" >nul 2>&1
cd /d "$work"
cl /nologo /c /std:c++20 /O2 /MD /EHsc /utf-8 /I"$Root\deps\fmt\include" "$Root\deps\fmt\src\format.cc" "$Root\deps\fmt\src\os.cc" || exit /b 1
lib /nologo /out:fmt.lib format.obj os.obj || exit /b 1
cl /nologo /external:W0 /c /std:c++latest /O2 /MD /EHsc /utf-8 /Zc:strictStrings /Zc:lambda /W1 $($inc -join " ") $($ext -join " ") $($defs -join " ") /Fo"$work\dllmain.obj" "$PSScriptRoot\dllmain.cpp" || exit /b 1
dumpbin /nologo /exports "$Ue4ssDll" > exports.txt
"@ | Set-Content "$work\step1.bat" -Encoding ascii
$o1 = cmd /c "$work\step1.bat" 2>&1 | Where-Object { $_ -notmatch 'vswhere|operable program' }
if ($LASTEXITCODE -ne 0) { $o1 | Select-Object -Last 30; throw "compile (or dumpbin) failed - see the output above" }
$names = Get-Content "$work\exports.txt" | Where-Object { $_ -match '^\s+\d+\s+[0-9A-F]+\s+[0-9A-F]{8}\s+(\S+)' } | ForEach-Object { $Matches[1] }
if ($names.Count -lt 1000) { throw "parsed only $($names.Count) exports from $Ue4ssDll - dumpbin output changed?" }
if ($names | Where-Object { $_ -like '*on_cpp_mods_loaded*' }) { throw "this UE4SS exports on_cpp_mods_loaded (RevOG / 4.0 line): its CppUserModBase vtable differs - use build.ps1" }
(@("LIBRARY UE4SS.dll", "EXPORTS") + ($names | ForEach-Object { "    $_" })) | Set-Content -Encoding ascii "$work\UE4SS.def"
@"
@echo off
call "$vcvars" >nul 2>&1
cd /d "$work"
lib /nologo /machine:x64 /def:UE4SS.def /out:UE4SS.lib || exit /b 1
link /nologo /DLL /OUT:main.dll /MACHINE:X64 dllmain.obj UE4SS.lib fmt.lib kernel32.lib user32.lib || exit /b 1
dumpbin /nologo /imports main.dll > imports.txt
"@ | Set-Content "$work\step2.bat" -Encoding ascii
$o2 = cmd /c "$work\step2.bat" 2>&1 | Where-Object { $_ -notmatch 'vswhere|operable program' }
if ($LASTEXITCODE -ne 0) { $o2 | Select-Object -Last 30; throw "link failed - see the output above" }
# every symbol main.dll imports from UE4SS.dll must be exported by the UE4SS.dll we built against
$need = @(); $in = $false
foreach ($l in Get-Content "$work\imports.txt") { if ($l -match '^\s+(\S+\.dll)\s*$') { $in = ($Matches[1] -ieq 'UE4SS.dll'); continue }; if ($in -and $l -match '^\s+[0-9A-F]+\s+(\S+)\s*$') { $need += $Matches[1] } }
$have = @{}; $names | ForEach-Object { $have[$_] = 1 }; $miss = @($need | Where-Object { -not $have.ContainsKey($_) })
if ($need.Count -lt 10) { throw "parsed only $($need.Count) imports from main.dll - dumpbin output changed?" }
if ($need | Where-Object { $_ -like '*on_cpp_mods_loaded*' }) { throw "main.dll imports on_cpp_mods_loaded: it was compiled against the wrong headers" }
if ($miss.Count) { throw "unresolved imports: $($miss.Count)" }
"built $work\main.dll for UE4SS.dll $ver : $($need.Count) imports, all resolved"
