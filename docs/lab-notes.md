# Lab notes (historical, 2026-11-25)

The working log kept while developing the mod, in the order it happened. Some statements are superseded by later sections (the mod was verified in game; see the README for the current state).


UE4SS C++ mod for Stellar Blade. ATOOL's `ModActor` blueprint refuses clip slots above 1000: `DataGet1/2/3` each hold one
`EX_IntConst 1000` in their bytecode (found 2026-11-25, see `sb-slot-organizer/docs/spike0-atool-limit.md`). This mod rewrites
those three constants in memory once ATOOL has loaded. Nothing of ATOOL's is modified on disk or redistributed.


> **Tested only with RevOG SB-UE4SS 1.3** (UE4SS.dll SHA-256 `E0CC51CE...DABE`). Any other UE4SS build is unsupported - see *Tested version* below.
## Status (2026-11-25)
VERIFIED IN GAME 2026-11-25: with this mod, clips at slots 1001 and 2000 load into ATOOL's list and play (see 'FIX FOUND' below). Earlier note: on load the log shows all three constants found at +97 and changed 1000 -> 9999 (`done: 3 constant(s) now 9999`), no crash. NOT yet verified: that ATOOL then actually plays a clip above 1000.

## Install
Copy `main.dll` to `<game>/SB/Binaries/Win64/ue4ss/Mods/AToolSlotLimit/dlls/`, add `enabled.txt` (contains `1`) and `config.txt` (`limit=9999`; `1000` = leave ATOOL unchanged). Restart the game (C++ mods do not hot reload).

## Build
Uses the same setup as SBCollide (against the installed UE4SS.dll, see header of `build.ps1`): copy `config.example.json` to `config.json`, add this folder to `D:\Modding\SBMods\CMakeLists.txt`, `cmake -S . -B Output`, then `powershell build.ps1`.
Note `out\main.dll` in the SBMods root is shared with SBCollide: install right after building.

## How
Polls every 2 s (engine tick) until `/Game/Mods/HD-ATOOL_P/ModActor.ModActor_C:DataGet1..3` exist, reads their `UStruct::Script` TArray (offset 0x60), replaces `1D E8 03 00 00` with `1D <limit>`, then stops polling. Sanity checks on the array before touching it. Logs every change.

## First in-game result (2026-11-25): patch applied, slot 6666 clip still not playable
Test pak `Eve_7400_SkyrimLeitoTest_P` (Leito_Anal_Missionary re-built at slot 6666, shows in PEFA). Log:
- `AToolSlotLimit`: DataGet1/2/3 patched at Script +97 (the 1000 guard is the first statement of each), as expected.
- PEFA, on play: `clip not in ATOOL's list (PEFA won't load it itself): .../anim/6666.6666`, then `skipped .../anim/6666a.6666a - made for nil` (partner table not loaded either).
- PEFA never loads clips itself (setting `pefa_load` off, a game-loader crash on 2026-11-16); it takes them from ATOOL's `anim3` array, which `DataGet3` fills (PEFA log: 336-337 clips, fewer than the ~351 slots installed). 6666 is not in that array.
So raising the guard did not make `DataGet3` list a slot-6666 clip. DataGet3 is short (1831 bytes): guard `<= 1000` at +97, then ~15 calls (asset registry style), no string/name constants. Next: probe the live `anim3` / `j3` / `jl3` with SBLive (`tools/sbl.ps1`) and call `DataGet3` by hand, to see how it picks clips; or try PEFA's `pefa_load=on` for this one clip.

## Live probe 2026-11-25 (SBLive, game running with the patch active)
- ATOOL actor: `j1=j2=j3=1`, `jl1..3=-1`, `anim1` 65, `anim2` 28, `anim3` 336 clips, max slot 900, no 6666.
- `anim3` == the Asset Registry listing under `/Game/Mods/HD-ATOOL_P/anim` (`GetAssetsByPath` returns exactly 336). So `DataGet3` just reads the registry; the slot index is not what picks clips.
- Registry knows slots 352 and 900 (`GetAssetByObjectPath`) but NOT 700 (ESAP pack, installed since Nov 20), 307, or 6666. Of 352 installed slots, the 16 missing from `anim3` are: ESAP 700-709, OldDroid 307-311 (other folder), test 6666. So 700 is missing while 900 is present: it is not a "> N" cutoff.
- `AR:ScanPathsSynchronous({"/Game/Mods/HD-ATOOL_P/anim"}, true)` run live did not add them (still 336).
Open: why the registry lists some mod-pak assets and not others (pak build attribute? registry source?). Not tested: `LoadAsset` of the 6666 path directly (PEFA's `pefa_load=on` route; crash history on 2026-11-16).

## LoadAsset test 2026-11-25
- `LoadAsset("/Game/Mods/HD-ATOOL_P/anim/6666.6666")` returns ok but the object stays nil; same for 700 (ESAP). 352 and 900 are resident. The test and ESAP containers are mounted (their `.ucas` are locked by the game) and their TOC structure (ver 2, chunk types, mount point `../../../SB/Content/`) matches working containers, so it is not a mount or pak-format problem. UE4SS `LoadAsset` goes through the Asset Registry, which does not know them.
- `sb-live/docs/live-pak.md` (2026-11-24): ATOOL loads all its clips at startup and keeps them resident (339 `anim/<N>`), so the clip loader, not `DataGet1-3`, decides which slots exist. That loader is not in the `DataGet` functions: no other limit constant (1001, 999, ...) in ModActor, NewBlueprint2/3 or NewWidgetBlueprint1.
- Not yet searched: `NewWidgetBlueprint2/3`, `NewBlueprint1`, `NewAnimBlueprint` (raw export did not land). ATOOL's own menu (a widget) is the likely startup batch loader.

## DataGet3 decoded (2026-11-25, from the container's uncompressed .ucas; script pointer = 16 bytes: count, FName index, number, owner export)
```
on3 = 0
loop:  if (on3 < 1000) {                      // <- the constant AToolSlotLimit rewrites (+97)
         on3 = on3 + 1
         path = os3 + str(on3) + "." + str(on3) + "'"      // AnimSequence'/Game/Mods/HD-ATOOL_P/anim/<n>.<n>'
         obj = LoadAsset_Blocking(MakeSoftObjectPath(path)); cast to AnimSequence; if ok: anim3.Add(obj)
         goto loop }
```
(from the first statement `anim3` clear, then the above). So the 1000 IS the loop bound and the loader loads slots 1..bound by exact path, which is why gaps are fine. Confirmed in game: slot 660 test pak loads, ESAP 700 / OldDroid 307 are missing because of IoStore container-ID clashes (see sb-slot-organizer scan).

## 1001 + 2000 test (09:16-09:17)
Patch logged `1000 -> 9999` for all three at 09:16:57, PEFA ran DataGet3 at 09:17:28 (list empty before, 336 after, no 660/1001/2000 in it). Slot 1001 and 2000 (same scenes that load at 660, container id unique) did NOT load. With the loop bound at 9999 they should have. Open: either the in-memory patch is not what DataGet3 executes, or loading fails for another reason above 1000. Next probe (needs the game running): read `A.on3` after the loop (9999 = patch effective, 1000 = not), then call `DataGet3` by hand.

## FIX FOUND 2026-11-25 09:28: ATOOL's class is replaced after the first patch
New build logs UFunction/Script addresses and re-checks every 5 s. First patch 09:27:49 (UFunction 0x3733f6de0...), then at 09:28:17 the same three functions are at NEW addresses (0x1b9912a5e0...) with the 1000 constant back: ATOOL's `ModActor_C` was re-created (level load). The old one-shot mod had patched the dead copy, which is why `on3` stayed 1000. Re-applying on the new copy: live probe shows `on1=on2=on3=9999`, `anim3` = 338 clips, and slots 1001 and 2000 ARE in ATOOL's list (the 660 test pak was replaced by the 1001/2000 one, so 660 is absent as expected).
Still to confirm: that 1001/2000 play, and the load cost of the longer loop (DataGet3 now tries 9999 paths).

## Tested version - read this first
**Tested with exactly one UE4SS build: RevOG SB-UE4SS 1.3.**

| | |
|---|---|
| UE4SS build | RevOG SB-UE4SS 1.3 (Nexus Mods, Stellar Blade) |
| `ue4ss\UE4SS.dll` SHA-256 | `E0CC51CE5B47D5BE82194510B0B4B4054DD15CE0322A983655A022F92D27DABE` |
| a line near the top of `ue4ss\UE4SS.log` | `UE4SS - v3.0.1 Beta #0 - Git SHA #08a0733` |
| built by | `build.ps1` against that UE4SS.dll's exports |
| verified in game | slots 1001 and 2000 play; a 982 to 1001 clip with partner tables plays with both partners; ATOOL's class re-creation is re-patched |

**Every other UE4SS build is unsupported and untested.** A native UE4SS mod links to C++ symbols of its host, so a DLL built for one UE4SS line does not belong in another. A second build for the Chrisr0/RE-UE4SS 3.1.0 line was written and removed on 2026-11-25: on 3.1.0-5 the mod loaded but never patched in the first run, and a rerun with a diagnostic DLL crashed while the game loaded the lobby (cause not analysed). If your `UE4SS.dll` hash differs from the one above, do not install this mod.
## License
MIT (see LICENSE). Independent community mod, not affiliated with Shift Up, ATOOL or UE4SS. Built against the UE4SS C++ API (MIT).
