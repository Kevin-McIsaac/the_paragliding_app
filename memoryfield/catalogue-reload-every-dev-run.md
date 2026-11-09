---
title: Catalogue reload on every dev run
created: '2026-11-09T01:40:00Z'
updated: '2026-11-09T01:40:00Z'
uuid: 5b597783-1e3d-4f73-82cf-35d735ebeaa2
summary: Dev runs lose SharedPreferences because XDG_DATA_HOME points at ephemeral /tmp, so the PGE catalogue re-downloads and re-imports on every launch.
---

`bin/dev_run.sh` inherits the agent export `XDG_DATA_HOME=/tmp/flutter-data` from the
`flutter-dev` skill. On Linux, `shared_preferences` stores its files under
`$XDG_DATA_HOME`, so every run starts with empty preferences.

Observed on 2026-11-09 in `dev_data/flutter.log`:

- `CATALOG_UPDATE_CHECK update_available=true | age_days=9809 | had_validators=false`
  on every launch.
- The app downloads the 2.24 MB PGE catalogue and imports 18,761 sites every start.
  That cost 47 s in debug and under 1 s in profile.
- All provider toggles and the catalogue date reset each run.

Fix (applied 2026-11-09): `bin/dev_run.sh` now points `XDG_DATA_HOME` at
`dev_data/app_data` when the inherited value is under `/tmp`, so preferences persist
without moving a human's real data location. Verified with two runs: the first
downloaded and imported the catalogue, the second logged no `CATALOG_UPDATE_CHECK`
(monthly throttle) and no download or import.

Sources: `lib/services/pge_sites_download_service.dart` (`checkForUpdate`), and the
`CATALOG_UPDATE_CHECK` log lines.
