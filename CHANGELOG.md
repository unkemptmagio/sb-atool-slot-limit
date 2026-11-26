# Changelog

## 0.2 - observability (2026-11-26)
- Own log file `AToolSlotLimit.log` (timestamped, rotated at 256 KB) in addition to the `[AToolSlotLimit]` lines in UE4SS.log.
- Startup identity: version, config read, host `UE4SS.dll` path + SHA-256 with a warning when it is not the tested build (RevOG SB-UE4SS 1.3).
- No silent waits: `waiting for ATOOL` once, `still waiting for ATOOL after N s` every 30 s, `ATOOL found after N s`; "no 1000 constant" / "odd Script array" are logged once instead of every poll; exceptions in the tick callback are caught and logged (first 5).
- Behaviour change (config only): a `limit=` below 1000, `0` or non-numeric text now means 1000 (ATOOL unchanged) with a warning; v0.1 used the default 9999 for non-numeric input and accepted 1..999 literally. The patch logic itself is unchanged (reviewed line by line against 0.1).
- Tested in game on RevOG SB-UE4SS 1.3: all log lines as above, 3 constants patched, re-applied after ATOOL's class was re-created, ATOOL listed a slot-1001 clip. `main.dll` SHA-256 `C42C8EF0AB1B1EBC16DBE62927F65CB6C600A12071D73CDC1DE15C325B7AFD76`.
- Known minor items for the next version (from the review, none blocking): no try/catch around `on_unreal_init`; after 5 tick exceptions logging stops without saying so; a `limit=1000` run says `done: 3 constant(s) now 1000` without noting that nothing was changed; SEH faults (access violations) are not caught; paths are limited to MAX_PATH; `widen()` of non-ASCII config text is garbled in the log.

## 0.1 (2026-11-25)
- Patch ATOOL DataGet1-3 slot guard in memory (unverified in game).

## 0.1 verified
- 2026-11-25 log: DataGet1/2/3 patched at +97, game kept running.

## 0.1 - verified in game (2026-11-25; the DLL and its log line report v0.1)
- Re-checks every 5 s and re-patches when ATOOL's ModActor_C is re-created (the one-shot patch hit a dead copy). Logs UFunction/Script addresses.
- Verified in game: slots 1001 and 2000 play. Limit configurable via config.txt `limit=` (default 9999). Extra cost: PEFA's one-time idle list build ~0.24 s (was ~0.1 s).

## Compatibility note (2026-11-25)
- The host UE4SS is the public RevOG SB-UE4SS 1.3 community build, not a private one; compatibility with SB-UE4SS 3.1.6 and Chrisr0 3.1.0-5 checked by symbol comparison: should not load (5 missing exports; not tested in game) [superseded: the Chrisr0 build below resolves every import there].

## Chrisr0 3.1.0 build (2026-11-25)
- build-chrisr0.ps1: second build of the same dllmain.cpp against Chrisr0/RE-UE4SS 3.1.0-5 headers (fmt 10.2.1). All 14 UE4SS imports resolve in Chrisr0 3.1.0-4, -5 and -6 (SB-UE4SS 3.1.6 is the identical file as -6). Not tested in game yet.

## In-game test plan (2026-11-25)
- docs/ingame-test-chrisr0.md and test/ingame-test.ps1 (prepare / swap / status by renaming the ue4ss folder; tested on a fake game folder only).

## Review fixes for the Chrisr0 build
- build-chrisr0.ps1 deletes stale outputs first, only accepts the three known Chrisr0 3.1.0 UE4SS.dll hashes (-AllowAnyUe4ss to override), refuses a UE4SS that exports on_cpp_mods_loaded, asserts the import list was parsed and does not contain on_cpp_mods_loaded, prints the real output when compile/link fails.
- README: removed a duplicated, contradictory compatibility block; documented the known untested differences (object cache default in -4, tick hook, no try/catch).

## Run A1 (2026-11-25)
- RevOG build: patched 3 constants, slot-1001 clip played. Test clip had a stale string-property size (digit-count re-slot bug in sb-slot-organizer, fixed); Run A2 pending.

## Run A2 (2026-11-25)
- Corrected slot-1001 test clip: Adam visible, 2 partner rows, no crash. Control passed; Chrisr0 Run B next.

## Chrisr0 build removed; tested version stated (2026-11-25)
- Removed build-chrisr0.ps1, the in-game test plan and swap helper: only RevOG SB-UE4SS 1.3 is built and supported. Earlier Chrisr0 entries above are historical (superseded).
- README states the single tested UE4SS (hash, log banner) first.
