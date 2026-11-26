# In-game test helper: switch the game between its normal UE4SS and a prepared Chrisr0 test UE4SS by RENAMING folders (instant, reversible,
# nothing is copied over or deleted). The game must be closed. Do not run a Vortex deploy/purge while swapped.
#   .\ingame-test.ps1 prepare -Game <SB folder> -ZipDir <extracted UE4SS_v3.1.0-x.zip> -ModDll <chrisr0 main.dll>
#   .\ingame-test.ps1 swap -To chrisr0 -Game <SB folder>      # ue4ss -> ue4ss.revog, ue4ss.test -> ue4ss
#   .\ingame-test.ps1 swap -To revog   -Game <SB folder>      # back; the test folder (with its UE4SS.log) is kept as ue4ss.test
#   .\ingame-test.ps1 status -Game <SB folder>
param([Parameter(Mandatory, Position = 0)][ValidateSet("prepare", "swap", "status")][string]$Cmd, [Parameter(Mandatory)][string]$Game,
      [string]$ZipDir, [string]$ModDll, [ValidateSet("chrisr0", "revog")][string]$To)
$ErrorActionPreference = "Stop"
$sb = if (Test-Path -LiteralPath (Join-Path $Game "SB\Binaries")) { Join-Path $Game "SB" } else { $Game }
$w = Join-Path $sb "Binaries\Win64"; $act = Join-Path $w "ue4ss"; $rev = Join-Path $w "ue4ss.revog"; $tst = Join-Path $w "ue4ss.test"
$REVOG = "E0CC51CE5B47D5BE82194510B0B4B4054DD15CE0322A983655A022F92D27DABE"
function Hash($p) { if (Test-Path -LiteralPath $p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { "(none)" } }
function Running { [bool](Get-Process -Name "SB-Win64-Shipping" -ErrorAction SilentlyContinue) }
function Show { "active ue4ss\UE4SS.dll : " + (Hash "$act\UE4SS.dll") + $(if ((Hash "$act\UE4SS.dll") -eq $REVOG) { "  (RevOG 1.3)" } else { "" }); "ue4ss.revog exists   : " + (Test-Path -LiteralPath $rev); "ue4ss.test exists    : " + (Test-Path -LiteralPath $tst) }
if (-not (Test-Path -LiteralPath $act)) { throw "no ue4ss folder at $act" }
switch ($Cmd) {
  "status" { Show }
  "prepare" {
    if (-not $ZipDir -or -not $ModDll) { throw "prepare needs -ZipDir and -ModDll" }
    if (Test-Path -LiteralPath $tst) { throw "$tst already exists - remove it first" }
    $zip = if (Test-Path -LiteralPath (Join-Path $ZipDir "ue4ss\UE4SS.dll")) { $ZipDir } else { Get-ChildItem -LiteralPath $ZipDir -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "ue4ss\UE4SS.dll") } | Select-Object -First 1 -ExpandProperty FullName }
    if (-not $zip) { throw "no ue4ss\UE4SS.dll under $ZipDir" }
    if ((Hash (Join-Path $zip "dwmapi.dll")) -ne (Hash (Join-Path $w "dwmapi.dll"))) { throw "the proxy dwmapi.dll differs between the package and the game; this helper only swaps the ue4ss folder" }
    Copy-Item -LiteralPath (Join-Path $zip "ue4ss") -Destination $tst -Recurse
    $m = Join-Path $tst "Mods"
    Copy-Item -LiteralPath (Join-Path $act "Mods\PEFA") -Destination (Join-Path $m "PEFA") -Recurse
    New-Item -ItemType Directory -Force (Join-Path $m "AToolSlotLimit\dlls") | Out-Null
    Copy-Item -LiteralPath $ModDll -Destination (Join-Path $m "AToolSlotLimit\dlls\main.dll")
    Set-Content (Join-Path $m "AToolSlotLimit\enabled.txt") "1" -Encoding ascii; Set-Content (Join-Path $m "AToolSlotLimit\config.txt") "limit=9999" -Encoding ascii
    Set-Content (Join-Path $m "mods.txt") @("BPModLoaderMod : 1", "PEFA : 1", "AToolSlotLimit : 1", "; Built-in keybinds, do not move up!", "Keybinds : 1") -Encoding ascii   # minimal set: nothing else can interfere
    "prepared $tst (UE4SS.dll " + (Hash "$tst\UE4SS.dll").Substring(0, 12) + ", mods: BPModLoaderMod, PEFA, AToolSlotLimit)"
  }
  "swap" {
    if (-not $To) { throw "swap needs -To chrisr0|revog" }
    if (Running) { throw "Stellar Blade is running: close it first" }
    if ($To -eq "chrisr0") {
      if (-not (Test-Path -LiteralPath $tst)) { throw "run prepare first ($tst is missing)" }
      if (Test-Path -LiteralPath $rev) { throw "$rev already exists: already swapped, or a leftover - check status" }
      if ((Hash "$act\UE4SS.dll") -ne $REVOG) { throw "the active ue4ss is not RevOG 1.3; refusing to swap" }
      Rename-Item -LiteralPath $act -NewName "ue4ss.revog"; Rename-Item -LiteralPath $tst -NewName "ue4ss"
    } else {
      if (-not (Test-Path -LiteralPath $rev)) { throw "$rev is missing: nothing to restore (already on RevOG?)" }
      if (Test-Path -LiteralPath $tst) { throw "$tst already exists: remove or rename it first so the test log is not lost" }
      Rename-Item -LiteralPath $act -NewName "ue4ss.test"; Rename-Item -LiteralPath $rev -NewName "ue4ss"
      if ((Hash "$act\UE4SS.dll") -ne $REVOG) { throw "restored folder does not hold RevOG 1.3 - check by hand" }
    }
    Show
  }
}
