# In-game test plan: AToolSlotLimit on the Chrisr0 UE4SS 3.1.0 line

Goal: decide whether the `chrisr0-3.1.0` build of the mod works in game. If it does, its UE4SS hashes move from `UNTESTED_UE4SS` to
`KNOWN_UE4SS` in sb-slot-organizer/slots.py (the tool then allows slots above 1000 there) and the docs lose "not tested".

What is NOT being tested: the slot tool itself (pak rewriting does not depend on UE4SS). Only "does the DLL load in Chrisr0's UE4SS,
patch ATOOL's three 1000 constants, and does a clip above slot 1000 play".

## Design (why it is safe and informative)
- **Whole-folder rename, nothing overwritten.** The proxy `dwmapi.dll` is byte-identical in both packages, so only the `ue4ss` folder differs.
  `ue4ss` -> `ue4ss.revog` and a prepared `ue4ss.test` -> `ue4ss`. Undo = the reverse renames. Your RevOG settings, mods and logs stay untouched
  in `ue4ss.revog`. The Chrisr0 run uses its own settings file (yours has 12 RevOG-only keys it does not know) and a MINIMAL mod set
  (BPModLoaderMod, PEFA, AToolSlotLimit, Keybinds) so nothing else can crash or confuse the result.
- **Control first.** The test clip is a copy of the Leito test pak re-slotted to **1001** (`tools/make_test_clip.py` in sb-slot-organizer; fresh
  container id, source untouched). It is first played on the current, known-good RevOG setup. If it plays there, a failure on Chrisr0 can
  only be the UE4SS build, not the clip. (Side effect: a pass also verifies a digit-count change 982 -> 1001, which the tool refuses today.)
- **Settings check before Run B:** open `ue4ss.test\UE4SS-settings.ini` and confirm `bUseUObjectArrayCache = false` and `HookEngineTick = 1` (true in the 3.1.0-4 zip's cache default would risk ATOOL's re-created class staying unpatched).
- **Two Chrisr0 builds**: 3.1.0-5 (PEFA's requirement) and 3.1.0-6 (= SB-UE4SS 3.1.6, what Nexus users mostly have). -4 stays untested.

## Prepare (no game running; does not change what the game loads)
1. Build the clip: `python tools/make_test_clip.py "<Paks>\~mods\_SkyrimPortTest\Eve_7400_SkyrimLeitoTest_P.utoc" 982 1001 "<Paks>\~mods\_SkyrimPortTest" --name Eve_7400_SkyrimLeitoTest1001_P`
2. `1001.wav` already exists in `LogicMods\HD-ATOOL_P\audio`. Add `1001 = Leito test 1001` to `ue4ss\Mods\PEFA\names.txt` (backup first); delete PEFA's `packs_rows.txt` / `packs_cache.txt` so it rebuilds.
3. Prepare the Chrisr0 test folder: `test\ingame-test.ps1 prepare -Game <SB> -ZipDir <extracted UE4SS_v3.1.0-5.zip> -ModDll D:\Modding\SBMods-chrisr0\build\main.dll`
   (refuses if the proxy dll differs; builds `ue4ss.test` beside `ue4ss`).

## Run A - control (current RevOG setup)
**Run A1 (2026-11-25 23:00): mod OK, clip played at 1001, no crash during play - but Adam was missing.** Cause found: a re-slot that changes the digit count left a stale StrProperty tag Size in the partner table (PEFA read 1 row instead of 2). Fixed in iostore._fix_strings and the clip rebuilt (**Run A2**: same steps; Adam must now be visible). Crash dumps at 23:01:49 coincide with game exit, like the earlier session (21:31:46).

1. Start the game, load a save, wait until Eve is in the world. Press O (PEFA), find "Leito test 1001", play it. Quit.
2. Pass = it plays. Read `ue4ss\UE4SS.log`: `[AToolSlotLimit] done: 3 constant(s) now 9999`. If this fails, stop: the clip or the digit change is the problem, not Chrisr0.

## Run B - Chrisr0 3.1.0-5
1. Close the game, then `test\ingame-test.ps1 swap -To chrisr0 -Game <SB>` (prints the active hash; expect `458839B7...`). Do not run Vortex deploy/purge while swapped.
2. Start the game, same steps as Run A (about 3 minutes). Also enter and leave a scene once (ATOOL's class is re-created; the mod must re-apply).
3. Close the game. `swap -To revog`, then `status` must show `E0CC51CE... (RevOG 1.3)`.

## Read the result (I read `ue4ss.test\UE4SS.log`)
| Log / game | Meaning | Next |
|---|---|---|
| banner `v3.1.0`, `[AToolSlotLimit] v0.1 loaded, limit 9999`, `done: 3 constant(s) now 9999 (3 expected)`, clip plays, no crash | **pass** | record hash as verified |
| mod not loaded / error mentions the DLL or an entry point | ABI mismatch beyond the symbols | rollback, fix headers/defines, rebuild |
| loaded, `no 1000 constant` or odd Script array | the Script offset (+0x60) differs on this UE4SS | per-build offset or read `MemberVariableLayout.ini` |
| loaded and patched but the clip is missing in PEFA | not a mod problem (names.txt / PEFA cache) | recheck prep step 2 |
| crash on start or in the scene | a `crash_*.dmp` appears in `ue4ss` | **say so**, rollback, do not retry before analysing |

## Rollback (any time, game closed)
`test\ingame-test.ps1 swap -To revog -Game <SB>` then `status`. The test folder with its log is kept as `ue4ss.test`. Remove the 1001 test pak
(`~mods\_SkyrimPortTest\Eve_7400_SkyrimLeitoTest1001_P.*`) and the `1001 =` line when done. Nothing else was touched.

## Then
Repeat Run B with 3.1.0-6 (`SB-UE4SS-3.1.6` in your Vortex staging holds the same file). Update `KNOWN_UE4SS`, the installer wording, README-USER.txt, docs/next.md, CHANGELOG; rebuild the release.
