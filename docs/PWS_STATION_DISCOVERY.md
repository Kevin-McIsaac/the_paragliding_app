# Weather Underground PWS Station Discovery

How to find and use nearby Weather Underground personal weather stations (PWS) as
observation sources for sites — programmatically, via the documented Weather Company
(TWC) APIs.

## Summary

Every `Site` already carries `latitude`/`longitude` (`lib/data/models/site.dart`). Those
coordinates are all that's needed to discover nearby PWS stations with a documented API
and pick the best observation station per site — no key shipped in the app, no manual
station hunting.

## The API (documented, not scraped)

WU's old `api.wunderground.com` API was retired in March 2019. Its replacement is
**The Weather Company Data API** (`api.weather.com`), and there is a free entitlement
program for **Personal Weather Station Contributors**:

- Portfolio spec: <https://docs.google.com/document/d/1eKCnKXI9xnoMGRRzOL1xPCBihNV2rOet08qpE_gArAY>
- Per-API docs linked from <https://twcapi.co> (e.g. [Location Service – Near](https://docs.google.com/document/d/14BKNJwPiU8T6UNFBzPn5NuNcAJjFcSWmMIc2TSqg51Q))
- PWS package contents: current conditions, 1/7-day recent history, daily/hourly history,
  `PWSHistoryAll` (long history), 5-day forecast, and the Near lookup below.
- Volume: **1500 calls/day, 30/minute** — ample for per-site discovery + one station's
  history pulls.

### Endpoints used

1. **Discovery** — nearest stations for a geocode (official spec: `twcapi.co/v3LSN`):

   ```
   GET https://api.weather.com/v3/location/near
       ?geocode=<lat>,<lon>      # WGS84, lat first
       &product=pws              # or: observation | airport | ski
       &format=json
       &apiKey=<user key>
   ```

   Returns up to 10 hits with `stationId`, `stationName`, `latitude`, `longitude`,
   `distanceKm`, `qcStatus` (`1` = QC passed, `-1` = no QC), `updateTimeUtc`.
   (`product=observation` returns nearest METAR stations — same shape.)

2. **Station metadata** — coordinates, elevation, anemometer height, station type:

   ```
   GET https://api.weather.com/v2/pwsidentity?stationId=<ID>&format=json&units=m&apiKey=...
   ```

3. **Live reading**:

   ```
   GET https://api.weather.com/v2/pws/observations/current?stationId=<ID>&format=json&units=m&apiKey=...
   ```

4. **History** (one request per day, `units=m` → km/h natively):

   ```
   GET https://api.weather.com/v2/pws/history/all?stationId=<ID>&format=json&units=m
       &date=YYYYMMDD&numericPrecision=decimal&apiKey=...
   ```

   Returns 5-minute-cadence observations; per reading `obsTimeUtc`, `winddirAvg` (degrees),
   and `metric.{windspeedAvg, windspeedHigh, windgustHigh, ...}`.

## Key policy (important)

- **Never embed a key in the app.** The key visible in the WU web dashboard page source is
  the website's own shared key — using it from a distributed app is fragile and against the
  spirit of the program.
- Instead: the user creates their own free key at
  <https://www.wunderground.com/member/api-keys> (any registered PWS user can), and pastes
  it into the app once. Keys are issued to registered *and active* PWS users; adding a
  device entry does not require owning a physical station.
- Validate the key with one `pwsidentity` call at setup, then store it in app settings
  (never in source control).

### Current implementation status (temporary exception)

The provider shipped (`WeatherUndergroundPwsProvider`) is wired with a **temporary shared
key** passed as `WUNDERGROUND_API_KEY` via `--dart-define` (like `FFVL_API_KEY`), until the
user-supplied-key flow exists. This knowingly bends the "never embed a key" policy: the
value is still recoverable from a shipped binary. The gap-probing strategy below exists
partly to make that shared key's 1500/day quota and shared provenance survivable.

## Discovery flow (per site, run once)

1. Take the site's `latitude`, `longitude` (already in the `Site` model).
2. `GET v3/location/near?product=pws&geocode=<lat>,<lon>&apiKey=<key>` → candidates with
   `distanceKm`.
3. Sort by distance; prefer `qcStatus == 1`; let the user confirm/override the pick.
4. Probe history depth for the chosen station with a few `pws/history/all` date probes
   (e.g. today, 1 year ago, 3 years ago) — discovery shows recency, not archive depth.
5. Store the chosen `stationId` on the site record (one-time user confirmation).
6. From then on, fetch observations per station ID — no further discovery calls.

## Known caveats

- The `v3/location/near` product is officially documented, but the endpoint host and key
  format are shared with the consumer web app; behaviour can change without notice. Wrap
  calls so a failure degrades gracefully (site works, just without an observation source).
- PWS data quality varies by station (drift, dropouts, junk readings). Apply the same
  sanity checks as forecast-accuracy does: drop counters with reasons, implausible-value
  warnings, provenance sidecars.
- History depth is per-station and unknown until probed; never promise "past accuracy"
  for a station whose archive hasn't been verified.
- Reference implementation of the flow in another project (Python CLI):
  `~/Projects/forecast-accuracy` (stage-2 backlog entry documents the verified endpoints).

## App integration (2026-09-05)

`WeatherUndergroundPwsProvider` (lib/services/weather_providers/) is the sixth entry in
`WeatherStationProviderRegistry`, alongside FFVL, BOM, METAR, NWS and Pioupiou.

**Discovery uses gap probing**, because `v3/location/near` is point-based (≤10 nearest
stations per call) while the map layer needs bbox coverage:

1. A session cache holds every discovered station (`DiscoveredPwsStation`), including the
   `distanceKm` each had from the probe point that found it.
2. For a viewport, sample points on a small grid (≤3×4, spacing ≈ 0.9 × the 12 km
   coverage radius, capped at 12 probes). Points within the coverage radius of a *fresh*
   known station are "covered".
3. Only uncovered points are probed; results merge into the cache. Once an area has been
   explored, panning back to it costs **zero API calls**.
4. Wind readings come from `pws/observations/current` for stations whose reading is older
   than the 10-minute TTL. All calls pass a simple 2-second throttle to respect the
   30/minute rate limit.
5. Stations with no `updateTimeUtc` within 2 hours are dropped as dead (QC status is shown
   in the observation type but does not filter).

UI: the PWS layer appears in the map filter dialog, nearby-sites screen, and about-screen
attribution like the other providers; the marker links to
`wunderground.com/dashboard/pws/<ID>`.

## Backlog

- **In-app runtime key entry**: replace the temporary shared key with a settings field
  where the user pastes their own free PWS key (from
  <https://www.wunderground.com/member/api-keys>), validated with one
  `pwsidentity` call at setup and stored in app settings — never in source control.
  Once that ships, remove `WUNDERGROUND_API_KEY` from `env.json`, the CI secret and
  `README_API_KEYS.md`, and retire the shared key.
- Per-site station pinning and history pulls (`pws/history/all`) — the discovery flow's
  steps 4–5, deferred with the first map-layer-only integration.

## Reference: verification log (2026-09-05)

Verified against the Mt Bakewell club station:

- `v3/location/near?geocode=-31.853,116.765&product=pws` → `IBURGE35` ("Burges",
  −31.85334, 116.76261) first at ~0.2 km, plus `IYORKYOR1`, `IYORK69`, `IYORK348`, …
- `pwsidentity?stationId=IBURGE35` → elevation 256 m, height 2.13 m, `stationType: other`.
- `pws/observations/current?stationId=IBURGE35` → live reading returned.
- `pws/history/all?date=20221204|20240115|20250915|20260830` → full days (244–288 obs/day,
  5-min cadence), continuous archive ≥3 years back, metric wind in km/h.
