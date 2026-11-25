# sb-atool-slot-limit

UE4SS C++ mod for Stellar Blade. ATOOL's `ModActor` blueprint refuses clip slots above 1000: `DataGet1/2/3` each hold one
`EX_IntConst 1000` in their bytecode (found 2026-11-25, see `sb-slot-organizer/docs/spike0-atool-limit.md`). This mod rewrites
those three constants in memory once ATOOL has loaded. Nothing of ATOOL's is modified on disk or redistributed.

## Status (2026-11-25)
Verified 2026-11-25: on load the log shows all three constants found at +97 and changed 1000 -> 9999 (`done: 3 constant(s) now 9999`), no crash. NOT yet verified: that ATOOL then actually plays a clip above 1000.

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
