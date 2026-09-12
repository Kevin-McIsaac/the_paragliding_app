# Plan: Holfuy stations as a map layer in the app

Status: proposed 2026-09-12. Decisions below are the owner's answers, recorded
so the build does not re-litigate them.

Adds **Holfuy** as a seventh weather station provider in `the_paragliding_app`,
sourced from a station file the federation publishes, built from the
1,537-station `state/holfuy_catalogue.json` in `paragliding_site_federation`.

It is an **add, not a fix**: there is no Holfuy code in the app today - no
`WeatherStationSource` value, no provider, no asset. The catalogue is the only
place the station **names** and **altitudes** exist; the federation's shared
cache stores Holfuy rows as `station_id, lat, lon, url` with no name and a null
elevation (`src/pws.py`'s `Station` has no `name` field at all).

Related reading:

- `paragliding_site_federation/docs/PLAN-holfuy-catalogue.md` - how the
  catalogue is built and why Holfuy has no discovery endpoint.
- `paragliding_site_federation/docs/APP-INTEGRATION.md` - the sites.csv
  switchover, which is a different migration.
- `docs/ADDING_WEATHER_PROVIDERS.md` (this repo) - the provider checklist this
  plan follows. It is stale in two ways and Phase 3 fixes them: it names the
  wrong file for the registry, and it predates `pushesProgressively`, BOM and
  WU PWS.

## Decisions (owner, 2026-09-12)

| Question | Answer |
|---|---|
| Surface | **Map station layer only.** No per-site "nearest Holfuy station" enrichment. |
| Licensing | **Positions and names are cleared for use, with attribution.** |
| Delivery | **Federation publishes a Holfuy-only station file; the app fetches it at runtime with a bundled fallback.** |
| Observations | **Positions always; live wind fetched on tap** - one request per station the user actually opens. |
| Scope | **Both repos** - federation data source and app consumer. |

## The constraint that shaped this plan

Measured against Holfuy this session, because it rules out the obvious design:

| Probe | Result |
|---|---|
| `holfuy.com/puget/mjso.php?k=<id>` | **Session-bound.** With no session it returns the same reading for every id (1000/142/351/1222 all gave 16.2 °C, 1023.2 hPa). With a cookie taken from the station page it returns the right station (142: 13 km/h, gust 22, 248°) - two requests per station, and clearly scraped. |
| `mjso.php?k=142,351` | `Please use our API at http://api.holfuy.com/live/` - **bulk is explicitly refused.** |
| `api.holfuy.com/live/?s=1000` | `{"errorCode":"no_access"}` - password-gated per station, documented ceiling of **3 stations**. |
| `widget.holfuy.com/?station=1000` | Server-renders the monitor page. With `&su=km/h` the values are km/h (142: speed 19, gust 25, avg 19.3, max gust 36). |
| `holfuy.com/en/weather/1000` | Still renders `la=45.76923 / lo=10.86437`, so the federation can still refresh coordinates. |

So a wind layer over 1,537 stations is not a provider away: it is one request
per station against an operator who points bulk consumers at an API capped at
three. What is buildable and honest is **positions for free, wind on demand**.

### Verified reading contract (the widget endpoint)

The parse target for on-tap readings, confirmed live on station 142:

```
GET https://widget.holfuy.com/?station=<id>&mode=detailed&su=km/h
User-Agent: TheParaglidingApp/1.0
```

| Field in the HTML | Meaning |
|---|---|
| `id="j_speed"` → `19` | current speed, **km/h** |
| `id="j_gust"` → `25` | current gust, km/h |
| `id="j_avg_speed"` → `19.3`, `id="j_max_gust"` → `36` | averages, km/h |
| `var owind=[[13,248],[15,266],[20,281],[19,275]];` | recent history as `[speed, degrees]`; **last pair gives the direction in degrees** - `id="j_dir"` is only cardinal (`W`) |
| `id="act_date"><b>113</b> sec. ago` | age; timestamp = now − 113 s |
| `var units ={"speed":"km\/h","temp":"C","height":"m"}` | **assert `speed == "km/h"` and abort the parse if not** - this is the guard against `su` silently not being honoured and a 3.6× error |
| `var stattr = {"id":142,"short_name":"EF","country":"NO","o_s":70,"o_e":140,…}` | metadata; `o_s/o_e` is the optimal wind direction range (future use) |

Offline stations render no `j_speed` value; the parser returns `null` rather
than inventing a reading.

## Phase 0 - federation: emit the app-facing station file (manual, like the catalogue)

The catalogue is **already built, and already manual**:
`state/holfuy_catalogue.json` holds 1,537 stations with names and altitudes,
produced by `python -m scripts.wu_pws_stations --catalogue-only` (~30 min at
1 req/s, run from a workstation), and `src/holfuy.py` documents the refresh as
manual-only - coordinates and the station list change rarely.

What does **not** exist yet is an app-facing file: `app/` holds only
`guides.json`, `sites.csv` and `site_weather_stations.csv`. And the weekly
`sync.yml` runs `src.pipeline`, which has **zero Holfuy references** - it never
reads the catalogue, and it must not start. Holfuy stays a manual job: the
weekly cron neither builds nor refreshes it.

So Phase 0 is one thing: a **network-free transform** from the catalogue that
already exists to `app/holfuy_stations.json`, run as part of the same manual
catalogue command. One manual run updates the audit catalogue and the app file
together, so the two cannot disagree.

1. **Writer** - `write_app_stations(path, catalogue)` in `src/holfuy.py`,
   called from the existing `--catalogue` / `--catalogue-only` branch of
   `scripts/wu_pws_stations.py`, right after `write_catalogue`, so both files
   come from the same in-memory catalogue. No new scheduled workflow;
   `src.pipeline` is untouched. Unlike the catalogue, this file **is tracked
   and published** - the app fetches it - so the manual run ends in a commit.
2. **Schema** - self-describing, so the licence travels with the data:

   ```json
   {
     "generated_utc": "2026-09-12T00:18:24Z",
     "source": "holfuy",
     "attribution": "Holfuy",
     "attribution_url": "https://holfuy.com/",
     "licence": "<the granted terms, verbatim>",
     "stations": [
       {"id": "142", "name": "THPK Ersfjord", "lat": 69.70017, "lon": 18.63842,
        "alt": 130, "country": "NO", "url": "https://holfuy.com/en/weather/142"}
     ]
   }
   ```

3. **Determinism** - sorted by integer id, stable key order, integer-ish
   `generated_utc` only from the catalogue's own timestamp. `http_freshness`
   compares ETag/Last-Modified, so a generator that reshuffles key order every
   run would make every app check look like a change and re-download 250 KB for
   nothing.
4. **Gates** - fail the run, do not publish a partial file, if the catalogue
   is missing, empty, or fewer than 90% of its entries have usable coordinates
   (the same completeness rule the catalogue build already uses).
5. **Licensing gate lift** - the owner's answer clears positions and names, so
   the two enforcement points documented in the federation README come down:
   `holfuy` leaves `OPT_IN_NETWORKS` (`src/pws.py`) and joins the default match
   pool, and the `.holfuy-preview` output gate is removed so Holfuy rows may
   enter `app/site_weather_stations.csv` (`.gitignore`'s entry for the preview
   file goes too). **This is a separate, visible change to shipped output** and it is not
   consumed by this feature - if it is not wanted yet, skip step 5 and publish
   the station file only. Record the attribution/licence text in the README's
   licensing section either way.
6. **Tests** - `tests/test_holfuy_stations.py`: the transform is deterministic
   across two runs; the completeness gate fails on a truncated catalogue; ids
   keep their integer ordering; the output parses as JSON with the declared
   keys. No network.

## Phase 1 - app: the station file (fetch + bundle)

Mirrors the existing `sites.csv` path in
`lib/services/pge_sites_download_service.dart`, without sharing its code:

1. **Bundled fallback** - commit `assets/data/holfuy_stations.json` (generated
   from the same script) and rely on the existing `assets/data/` pubspec entry.
   Offline-first: a pilot at a launch with no signal still sees Holfuy pins.
2. **Download service** - `lib/services/holfuy_stations_download_service.dart`,
   reusing `lib/utils/http_freshness.dart`'s `isRemoteNewer` for the
   ETag/Last-Modified/age decision. Same shape as the PGE service: a HEAD-style
   freshness check on a 7-day cadence (cheap, and the file only moves when
   someone re-runs the manual catalogue), off the startup path, swallowing
   every failure and falling back to the bundled copy. A new service rather
   than a generalisation of `PgeSitesDownloadService`, so the sites import
   (the flight-log-critical path) is not destabilised by a station file.
3. **Parser** - one function, `parseHolfuyStations(String json) ->
   List<WeatherStation>`, pure and unit-testable. Each entry becomes a
   `WeatherStation` with `source: holfuy`, `name`, `elevation`, `dataUrl`, and
   **no `windData`**. An entry with missing or non-finite coordinates is
   skipped and **counted**, never coerced to 0,0.
4. **URL constant** - add `HolfuyStationsConfig.catalogUrl` pointing at
   `raw.githubusercontent.com/Kevin-McIsaac/paragliding_site_federation/main/app/holfuy_stations.json`,
   public so a `network`-tagged test can assert it still serves usable data -
   the same pattern as `PgeSitesConfig.catalogUrl` and
   `AirspaceCountryService.countryDataUrl()`.

## Phase 2 - app: provider and on-demand readings

1. **Enum** - `WeatherStationSource.holfuy` in
   `lib/data/models/weather_station_source.dart`, with a doc comment stating
   the position/observation split.
2. **Provider** - `lib/services/weather_providers/holfuy_weather_provider.dart`:

   - `displayName: 'Holfuy'`,
     `description: 'Launch-site wind stations (worldwide)'`,
     `attributionName: 'Holfuy'`, `attributionUrl: 'https://holfuy.com/'`,
     `requiresApiKey: false`, `pushesProgressively: false`.
   - `fetchStations(bounds)` - load the file (download-if-needed, cached 24 h),
     filter in memory to `bounds`, return stations without wind. Zero Holfuy
     requests: the file is the federation's, not Holfuy's.
   - `fetchWeatherData(stations)` - **returns cached readings only and never
     touches the network.** `WeatherStationService.getWeatherForStations`
     groups by source and calls this with every station of that source; for
     Holfuy that must be a no-op fan-out, or a pan across the Alps becomes
     hundreds of scraped requests. A test asserts it issues zero requests for
     N stations.
   - `requestReading(String stationId) -> Future<WindData?>` - the on-tap path.
     Single-flight, serialised, at least 1 s between requests, results cached
     per station for 5 minutes. Parses the widget contract above, asserting the
     declared units before trusting the numbers.
3. **Registry** - add to `_providers` in
   `lib/services/weather_providers/weather_station_provider_registry.dart`.
4. **Constants** - `lib/utils/map_constants.dart`:
   `holfuyStationListCacheTTL = 24 h`, `holfuyReadingCacheTTL = 5 min`,
   `holfuyMinRequestInterval = 1 s`.

## Phase 3 - app: display

1. **Filter toggle** - `lib/presentation/widgets/map_filter_dialog.dart`: add
   `holfuyEnabled` (constructor, `_holfuyEnabled` state, `initState`, the
   checkbox next to BOM/WU). The `onApply` callback is **positional**
   (`map_filter_dialog.dart:1133`, 16 arguments), so the change threads
   through `nearby_sites_screen.dart`: `_holfuyEnabled` state, the
   `weather_provider_holfuy_enabled` preference load/save, the
   `_DraggableFilterDialog` wrapper, `_handleFilterApply`, and the loading
   overlay's enabled-source filter. This is the checklist in
   `docs/ADDING_WEATHER_PROVIDERS.md`; skipping any one of the five leaves a
   checkbox that does nothing.
2. **Marker** - `lib/presentation/widgets/weather_station_marker.dart`: a
   Holfuy station with no reading must not read "No wind data", which is what
   the current WU-specific fallthrough says. Add a source-aware tooltip:
   name, altitude, and "Tap for wind". The existing
   `_isNoDataStation`/`_isPendingStation` helpers are WU PWS-specific and
   should gain a Holfuy counterpart rather than being widened.
3. **Station dialog** - `_showStationDialog`: when a Holfuy station has no
   cached reading, call `requestReading` and render a loading state, then the
   wind (speed/gust/direction/age) when it lands. Failures degrade to the
   station details and a link, never a spinner that never stops. Always offer
   **"View on Holfuy"** via `dataUrl`. Report the reading back to the screen so
   the marker gains its wind, rather than leaving the map stale.
4. **Observation type** - `WeatherStation.inferObservationType` returns
   **"Marine Buoy" for every numeric id**, which is every Holfuy station. Set
   `observationType` explicitly when constructing Holfuy stations ("Holfuy
   launch station") and add a regression test for the helper.
5. **Attribution** - `lib/presentation/screens/about_screen.dart`, Weather Data
   card: a compact Holfuy link (`https://holfuy.com/`), matching the FFVL/BOM
   entries. The licence text now also travels in the station file.
6. **Doc** - refresh `docs/ADDING_WEATHER_PROVIDERS.md`: correct the registry
   file path, and document `pushesProgressively`, the on-demand reading
   pattern, and the unit-assertion rule as a first-class option.

## Phase 4 - tests

Read `.claude/skills/testing/SKILL.md` before writing these; fixtures go
through `TestHelpers.fixturePath`, the database stays in memory.

1. Station-file parse: a fixture of the published file yields the right count,
   names, altitudes and coordinates.
2. **Negative test:** a fixture entry with missing/NaN coordinates is skipped
   and counted, not placed at 0,0.
3. Bbox filter: only stations inside bounds are returned; a wide viewport
   returns the full set.
4. **Zero-fan-out test:** `fetchWeatherData` with N Holfuy stations makes zero
   network calls and returns only previously cached readings.
5. Reading parse, two fixtures: the km/h page (assert 19/25/275°/age) and an
   **m/s page, which must be rejected** because the declared units disagree -
   this is the guard that stops a silent 3.6× error.
6. Offline page fixture → `null`, no exception.
7. Throttle and cache: with a fake clock, two taps inside the interval issue
   one request; a tap after 5 minutes issues a second.
8. Filter toggle: enabling/disabling Holfuy round-trips through
   `SharedPreferences` and changes the enabled-provider set.
9. `network`-tagged: the published `holfuy_stations.json` URL still serves
   parseable data (skipped by default, like the other live-API tests).

## Phase 5 - verification (artifact, not status)

1. **Coordinate spot-check** at map level: three catalogue stations on
   different continents land in the right place. A lat/lon transposition
   parses cleanly and puts a station in the wrong hemisphere - the failure the
   catalogue plan warns about, and row counts will not catch it.
2. **Prove the unit guard fails without the fix:** with the m/s fixture in
   place, revert the unit assertion and watch test 4.5 go red. A guard only
   ever seen green is unverified.
3. **Prove the fan-out guard fails:** make `fetchWeatherData` delegate to
   `requestReading` and confirm the zero-fan-out test fails.
4. **Count requests, don't eyeball the map:** pan a viewport containing 100+
   Holfuy stations and assert the logs show one file load and zero reading
   requests; then tap one station and assert exactly one.
5. **Drive production code paths** (run-app skill): launch on Linux desktop,
   enable Holfuy, confirm pins appear with names, tap one and see live wind
   render. Then disable the toggle and confirm the pins disappear.
6. `flutter analyze` clean and `flutter test` green from
   `the_paragliding_app/`.

## Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Widget HTML changes | It is scraping, and the catalogue plan already found Holfuy retires routes (the map overview went in 2026-09) | Feature-detect the fields; degrade to a link-only station card, never a wrong number |
| `su=km/h` is ignored for some station | 3.6× wind error that looks plausible | Assert `var units.speed == "km/h"` and abort otherwise; m/s fixture test |
| Holfuy blocks the app's IP | Bursts of requests have been refused before | One request per user tap, cached 5 min, serialised, identifying User-Agent |
| Station file grows | 1,537 stations ≈ 250 KB | Plain JSON is fine against a 2.2 MB `sites.csv`; gzip only if it grows |
| Positional `onApply` churn | 16-argument positional signature; a miss is a silent no-op | Follow the provider checklist exactly; toggle test in Phase 4 |

## Out of scope

- **Per-site enrichment.** Showing "nearest Holfuy station" on site details or
  in flyability is a deliberate non-goal of this plan (the owner chose the map
  layer). The federation's matched `site_weather_stations.csv` path is where
  that would live, and the app does not yet consume it at all.
- **Bulk observation redistribution.** Readings are fetched on demand, by the
  device, and not bundled or republished.
- **Holfuy's `o_s/o_e` optimal-direction metadata**, parsed but unused here; it
  would make a nice per-station "good direction" indicator later.
- **Renaming `pge_sites`** and the rest of `APP-INTEGRATION.md`'s app phases.
