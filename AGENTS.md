# AGENTS.md

One file: `dllmain.cpp`. Build: `build.ps1` (see README). Log tag `[AToolSlotLimit]` in `ue4ss/UE4SS.log`.
- Never edit ATOOL files on disk; patch memory only. Never commit `config.json`, `*.dll`.
- Crash -> `.dmp` in `ue4ss/`; say so before retrying. Keep README/CHANGELOG current.
