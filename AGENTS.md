# AGENTS.md

One file: `dllmain.cpp`. Build: `build.ps1` (see README). Log tag `[AToolSlotLimit]` in `ue4ss/UE4SS.log`.
- Never edit ATOOL files on disk; patch memory only. Never commit `config.json`, `*.dll`.
- Crash -> `.dmp` in `ue4ss/`; say so before retrying. Keep README/CHANGELOG current.
- Two builds: build.ps1 (RevOG SB-UE4SS 1.3) and build-chrisr0.ps1 (Chrisr0 3.1.0-x); the same dllmain.cpp must compile against both trees.
