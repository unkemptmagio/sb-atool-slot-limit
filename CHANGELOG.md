# Changelog

## 0.1 (unreleased)
- Patch ATOOL DataGet1-3 slot guard in memory (unverified in game).

## 0.1 verified
- 2026-11-25 log: DataGet1/2/3 patched at +97, game kept running.

## 0.2 (2026-11-25)
- Re-checks every 5 s and re-patches when ATOOL's ModActor_C is re-created (the one-shot patch hit a dead copy). Logs UFunction/Script addresses.
- Verified in game: slots 1001 and 2000 play. Limit configurable via config.txt `limit=` (default 9999). Extra cost: PEFA's one-time idle list build ~0.24 s (was ~0.1 s).

## Compatibility note (2026-11-25)
- The host UE4SS is the public RevOG SB-UE4SS 1.3 community build, not a private one; compatibility with SB-UE4SS 3.1.6 and Chrisr0 3.1.0-5 checked by symbol comparison: not loadable (5 missing exports).
