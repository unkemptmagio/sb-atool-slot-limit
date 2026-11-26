# Changelog

## 0.1 (unreleased)
- Patch ATOOL DataGet1-3 slot guard in memory (unverified in game).

## 0.1 verified
- 2026-11-25 log: DataGet1/2/3 patched at +97, game kept running.

## 0.2 (2026-11-25)
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
