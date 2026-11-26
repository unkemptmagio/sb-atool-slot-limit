# sb-atool-slot-limit

Optional UE4SS C++ mod for Stellar Blade that lifts ATOOL's 1000-slot limit at runtime. Nothing of ATOOL's is modified on disk or redistributed.

> ## Tested version - read this first
> **Tested with exactly one UE4SS build: RevOG SB-UE4SS 1.3.**
>
> | | |
> |---|---|
> | `ue4ss\UE4SS.dll` SHA-256 | `E0CC51CE5B47D5BE82194510B0B4B4054DD15CE0322A983655A022F92D27DABE` |
> | a line near the top of `ue4ss\UE4SS.log` (line 2, after a timestamp) | `UE4SS - v3.0.1 Beta #0 - Git SHA #08a0733` |
>
> **Every other UE4SS build is unsupported and untested** (a native UE4SS mod links to C++ symbols of its host). A test on Chrisr0/RE-UE4SS 3.1.0-5 ended in a game crash while loading; the cause was not analysed. If your `UE4SS.dll` hash differs, do not install this mod. The SHA-256 is the reliable check.

## Requirements
- **RevOG SB-UE4SS 1.3** (see above).
- **ATOOL (HD-ATOOL_P)** installed. The mod waits for ATOOL's class and has never been run without it.

## Install
Normally through SlotOrganizer's `install-atool-limit.bat`, which refuses any other UE4SS build. By hand, only on the tested build: copy `AToolSlotLimit\{dlls\main.dll, enabled.txt, config.txt}` to `SB\Binaries\Win64\ue4ss\Mods\AToolSlotLimit\`. Uninstall: delete that folder.

## Settings
- `config.txt`: `limit=9999` is the new slot limit. `limit=1000` leaves ATOOL unchanged. A value below 1000, `0` or text that is not a number is not supported: the mod uses 1000 (ATOOL unchanged) and logs a warning - so a typo switches the feature off instead of guessing.
- `enabled.txt`: `1` on, `0` off.

## How it works
ATOOL's `ModActor` blueprint functions `DataGet1/2/3` each hold one Kismet `EX_IntConst 1000` (`1D E8 03 00 00`) at `Script + 97`. Once ATOOL's class is loaded the mod finds those bytes in `UStruct::Script` (a `TArray<uint8>` at `+0x60`, the game's own UE 4.26 layout) and writes the configured limit. It polls every 2 s until patched, then every 5 s, because ATOOL's class is re-created after load and must be patched again. The one source file is `dllmain.cpp`.

## Verified in game (RevOG SB-UE4SS 1.3, 2026-11-25)
- Log: `[AToolSlotLimit] v0.2 loaded, limit 9999`, then `done: 3 constant(s) now 9999 (3 expected)`.
- Clips at slots 1001 and 2000 appear in ATOOL's list and play; a clip re-slotted to 1001 with partner tables plays with both partners.
- ATOOL's class re-creation is re-patched. No crash while playing.

## If something goes wrong
The mod writes the same lines to two places: `<game>\SB\Binaries\Win64\ue4ss\UE4SS.log` (search for `AToolSlotLimit`) and its own timestamped file `Mods\AToolSlotLimit\AToolSlotLimit.log` next to `config.txt` (rotated at 256 KB, one `.1` copy).
- **Working:** `v0.2 loaded, limit 9999`, `host UE4SS: ... - the tested build (RevOG SB-UE4SS 1.3)`, `engine tick callback is running`, then `done: 3 constant(s) now 9999 (3 expected)`.
- **`host UE4SS: ... NOT the tested build`:** you are not on RevOG SB-UE4SS 1.3 - unsupported.
- **No `v0.2 loaded`:** the mod did not load (wrong UE4SS build, wrong folder, `enabled.txt` = 0).
- **`waiting for ATOOL` / `still waiting for ATOOL after N s` (every 30 s):** ATOOL's class is not loaded (not installed, or not loaded yet); `ATOOL found after N s` follows when it appears.
- **`odd Script array` / `no 1000 constant` (logged once per function):** ATOOL's data differs from the version the mod was made for.
- **`config: limit=... is below 1000`:** fix `config.txt` (see Settings).

Attach `AToolSlotLimit.log` (or the `UE4SS.log` lines containing `AToolSlotLimit`) when asking for help. Both contain your game folder path, which can include your Windows user name.

## Build
`build.ps1` (Windows, Visual Studio 2022 C++ build tools) compiles `dllmain.cpp` against a UE4SS source tree and links against an import library generated from the exports of the installed `UE4SS.dll`, so every import exists in that build. The setup steps are in the header of the script. `config.json` (the game path) is local and not committed.

## Lab notes and history
`docs/lab-notes.md` is the development log (superseded in places); `CHANGELOG.md` lists changes. The spike that found the limit: https://github.com/unkemptmagio/sb-slot-organizer/blob/master/docs/spike0-atool-limit.md

## License
MIT (see LICENSE). Independent community mod, not affiliated with Shift Up, ATOOL or UE4SS. Built against the UE4SS C++ API (MIT).
