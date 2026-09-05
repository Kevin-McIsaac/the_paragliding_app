# Implementation prompt — paste into the_paragliding_app session

Read `docs/PWS_STATION_DISCOVERY.md` first — it documents the verified Weather Company
(TWC) APIs and the key policy. Implement PWS station discovery for sites:

## Goal

Let the user assign an observation station to each site: discover nearby Weather
Underground personal weather stations (PWS) programmatically from the site's own
coordinates, confirm the pick once, then fetch live and historical observations per
station ID.

## Requirements

1. **API key onboarding**
   - New setting: WU API key (user-supplied, from wunderground.com/member/api-keys).
     Never hardcode a key; never commit one. Store via the existing settings mechanism
     (same habit as other user prefs in `preferences_helper.dart`).
   - Validate at save time with one `GET /v2/pwsidentity?stationId=IBURGE35&...` style
     call; on failure show an actionable error (key invalid / network), don't crash.

2. **Discovery service** — new `PwsDiscoveryService` (mirror `weather_service.dart`
   conventions; `LoggingService` for diagnostics, never `print`):
   - `Future<List<PwsCandidate>> findNearby({required double lat, required double lon, int radiusKm})`
     calling `GET https://api.weather.com/v3/location/near?geocode=<lat>,<lon>&product=pws&format=json&apiKey=<key>`
   - `PwsCandidate`: `stationId, stationName, latitude, longitude, distanceKm, qcStatus, updateTimeUtc`.
     Parse defensively (nullable fields); tolerate extra fields.

3. **Site linkage**
   - Add nullable `observationStationId` (String) to the `Site` model + DB migration
     (follow `docs/DATABASE.md` migration process; bump schema version).
   - One-time assignment UI on the site-details screen: "Find nearby stations" → sorted
     candidate list (distance, name, QC flag) → user picks one (or none) → saved to the
     site. Re-running discovery replaces the pick; it is never automatic on app start.

4. **Observation fetch service**
   - `current`: `/v2/pws/observations/current?stationId=...&units=m` → latest
     speed/gust/direction for the site's observation display.
   - `historyAll`: `/v2/pws/history/all?stationId=...&units=m&date=YYYYMMDD` — one request
     per day; metric units natively (km/h), no conversion.
   - All responses cached to disk (app documents dir) keyed by station+date, idempotent
     re-runs, network only on cache miss/expiry — mirror the app's provider TTL habits.
   - Rate-limit-friendly: no parallel bursts; 30/min, 1500/day headroom is ample.

5. **Data quality (mandatory)**
   - Drop or flag readings failing sanity checks (null wind, negative speeds, speed
     spikes vs station history); always with reason + count in logs (drop counters must
     reconcile: kept + dropped = fetched).
   - Surface anomalies at WARNING even in non-verbose mode.
   - No interpolation of raw 5-min observations; instant readings only.

6. **Testing (`testing` skill rules apply)**
   - Every API response used by a test is a recorded JSON fixture under
     `test/fixtures/pws/` (use real IBURGE35 excerpts: discovery, identity, current,
     one history day).
   - Tests never hit the network (same rule as the `network` test tag).
   - Cover: candidate parsing, QC preference ordering, migration up/down, cache
     idempotency, drop-counter reconciliation.

7. **Quality gates**
   - `flutter analyze` after the multi-file change; fix everything.
   - Run the `network`-tagged integration test manually once against the real API to
     confirm shape assumptions, then record fixtures and never hit the network again.

## Out of scope (for this task)

- Nothing in the flyability logic changes — this is observation sourcing only.
- No background scheduler, no beacon capture modes (FFVL/PiouPiou), no UI beyond the
  site-details picker.
- Do not persist or commit any key material or personal flight context.
