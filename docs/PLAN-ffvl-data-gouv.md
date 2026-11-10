# Design: FFVL weather beacons from data.gouv.fr

Status: implemented 2026-11-10.

Implementation notes:

- The provider logs `skipped` for every unusable reading, including stale ones.
- The unit tests drive `fetchStations` through `MockClient` instead of exposing
  static parsers.

The FFVL moved its weather beacon data from the keyed `data.ffvl.fr` API to two
public files on data.gouv.fr. This design replaces the FFVL provider's transport
and parsing, removes the API key, and keeps the existing map layer, cache shape
and station identity. It follows the provider patterns already used by Pioupiou
(global fetch-all, dual TTL) and Holfuy (injected HTTP client, pure parsers,
`network`-tagged live test).

Related reading:

- [Weather Station Sources](WEATHER_STATION_SOURCES.md) - the seven layers.
- [Weather Station APIs](api/WEATHER_STATIONS.md) - per-provider caching.
- [Adding Weather Providers](ADDING_WEATHER_PROVIDERS.md) - the provider contract.
- `the_paragliding_app/lib/services/weather_providers/ffvl_weather_provider.dart` -
  the code this design replaces.
- `the_paragliding_app/lib/services/weather_providers/pioupiou_weather_provider.dart` -
  the closest existing cache pattern.
- `the_paragliding_app/lib/services/weather_providers/holfuy_weather_provider.dart` -
  the testable HTTP/client and parser pattern.

## 1. What changed upstream

Verified on 2026-11-10 from the dataset API, the `/informations` page and the
two published files:

| Fact | Value |
|---|---|
| Dataset | Réseau de balises météo de la FFVL |
| Dataset id | `6ac7affa6bb0f2237411d605` |
| Publisher | Fédération Française de Vol Libre, certified public-service badge |
| Licence | Licence Ouverte / Open Licence 2.0 (Etalab) |
| Access | No key, no account, CORS `*` |
| Beacon file | `balises.json`, about 237 KB, published daily |
| Reading file | `releves.json`, about 33 KB, published every 5 minutes |
| Coverage | 644 beacons, 540 not in maintenance |
| Readings | 178 in the probe, one latest reading per beacon |
| Reading age | median 7-12 min, maximum 87 min |
| Station networks | ADISON, OPENWINDMAP, HOLFUY, SENCROP, CTIC, METEOCONCEPT, EUCLIDE, IWEATHAR_PULL, GREEN_CITIZEN, PETIT_BALLON, WINDGURU, AUTRE |

The old `https://data.ffvl.fr/api/` endpoints are not part of this design. The
old source needed a key compiled into every build. The new source does not.

### Stable resource URLs

`static.data.gouv.fr` publishes each release under a dated folder and serves it
with `Cache-Control: max-age=2592000` (30 days). A dated URL must never be
hard-coded: it goes stale, and a CDN or client cache keeps it stale for a month.

Use the resource-id endpoints instead. They answer with a 302 to the current
dated file on every request. Verified 2026-11-10:

```
balises: https://www.data.gouv.fr/api/1/datasets/r/8d795154-9145-4ab2-99de-6768a36f31ea
releves: https://www.data.gouv.fr/api/1/datasets/r/047b2ab9-627f-4e5f-9d68-5b948433c61d
```

`package:http` follows the redirect for GET by default. The final response is
`200 application/json`. A resource id is a stable dataset identifier: on
2026-11-10 both ids redirected to the current dated files. Check them again if
a request returns 404.

If FFVL replaces a resource instead of updating it, these ids return 404 or 410.
The design treats that as a named failure, not a silent empty map. See section
10.

### Fields the app uses

`balises.json` (array):

| Field | Use |
|---|---|
| `idBalise` | station id, `ffvl_<id>` |
| `nom` | station name |
| `latitude`, `longitude` | position, required |
| `altitude` | elevation, metres |
| `departement` | suffix in the display name |
| `station_type` | observation type |
| `en_maintenance` | skip when `1` or `"1"` |

`releves.json` (array):

| Field | Use |
|---|---|
| `idbalise` | join key (`idbalise`, unlike `idBalise`) |
| `date` | observation time, ISO 8601 with offset |
| `vitesseVentMoy` | average wind, km/h |
| `vitesseVentMax` | gust, km/h, optional |
| `directVentMoy` | direction, degrees |

### Fields the app must not read

`balises.json` includes `contact_name`, `contact_phone`, `contact_email_adr`,
`remarques` and `alert_message`. The first three are personal data. The app must
not parse, log or store any of them. Ignoring them also keeps the parsed model
small.

The reading file has `temperature`, `pression`, `hydrometrie`, `LUM`, `u_sol`,
`u_bat` and `directVentInst`. The map layer does not use them. `directVentInst`
is deliberately not substituted for `directVentMoy`: averaging is the layer's
existing contract.

## 2. The problem in the current code

The current provider is structurally right. Three things must change for the new
source. The second is a serious efficiency defect:

1. **Transport.** `_fetchAllBeacons` builds keyed `data.ffvl.fr` URLs
   (`ffvl_weather_provider.dart:235` and `:287`), and `isConfigured` requires
   `ApiKeys.ffvlApiKey` (`:65`).
2. **Refresh re-downloads the catalogue.** `_refreshMeasurements` calls
   `_fetchAllBeacons()` (`:416`), which fetches the beacon list *and* the
   readings. With the old API that was tolerable. With data.gouv.fr it would
   download 237 KB + 33 KB every 5 minutes, about 78 MB per day if the map
   stays open.
3. **Parsing assumes the old payload.** It reads `url` and the embedded
   `last_wind_speed_*` fields, and compares `en_maintenance` with the string
   `'1'`. The new files have no `url` and no embedded readings, and
   `en_maintenance` is an integer.

The dual-TTL cache, the world-bbox warm-up, the bbox overlap exit, the
maintenance skip, the department names and the `ffvl_<id>` station id all stay.

## 3. Decisions (proposed)

| Topic | Decision |
|---|---|
| Transport | The two `/api/1/datasets/r/<id>` endpoints. Never a dated static URL. |
| Cache | Keep the dual TTL. Beacon list 24 h, readings 5 min. |
| Refresh | Readings only. The beacon list is never re-downloaded on the 5-minute path. |
| Key | Remove `FFVL_API_KEY` from the app, CI and docs. |
| Maintenance | Skip, unchanged. |
| No-reading beacons | Keep every active beacon, with `windData == null` when there is no usable reading. |
| OpenWindMap | Keep them in the FFVL catalogue. Their readings arrive through the existing Pioupiou layer, and the 150 m deduplication drops the duplicate. |
| Reading age | Attach wind only when the reading is at most 2 hours old. |
| Contact fields | Never parsed. |
| Attribution | FFVL, data.gouv.fr and the Etalab 2.0 licence. |
| Failure | Keep the last good cache. Never fall back to the old keyed API. |

## 4. Provider design

### 4.1 Identity

Unchanged: `WeatherStationSource.ffvl`, `displayName` `FFVL Beacons`,
`pushesProgressively == false`, station id `ffvl_<idBalise>`, cache key
`weather_provider_ffvl_enabled`.

Changed:

```dart
@override
bool get requiresApiKey => false;

@override
Future<bool> isConfigured() async => true;

@override
String get description => 'French paragliding weather beacons (data.gouv.fr)';

@override
String get attributionName => 'FFVL (data.gouv.fr)';

@override
String get attributionUrl =>
    'https://www.data.gouv.fr/datasets/reseau-de-balises-meteo-de-la-ffvl-federation-francaise-de-vol-libre';
```

### 4.2 Cache model

The cache keeps the parsed catalogue separately from the derived stations, so a
reading refresh does not need to download or re-parse `balises.json`.

```dart
class _Beacon {
  final String id;              // idBalise as a string
  final String? name;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? department;
  final String stationType;
}

class _GlobalCacheEntry {
  final List<_Beacon> beacons;
  final List<WeatherStation> stations;   // beacons + readings, rebuilt on refresh
  final DateTime beaconListTimestamp;
  final DateTime measurementsTimestamp;
  final LatLngBounds bounds;
}
```

Memory is about 540 small records plus 540 stations. That is the same order as
today.

Two private futures guard network work: `_pendingCatalogue` for the full load
and `_pendingRefresh` for the readings. A caller that arrives during either
awaits the in-flight future, then reads the cache. This keeps a fast pan from
starting a second download.

### 4.3 Fetch flow

```
fetchStations(bounds):
  if cache == null or cache.beaconListExpired:
      await _loadCatalogue()                 # 2 requests, at most once per 24 h
  else if cache.measurementsExpired and any station in bounds:
      await _refreshReleves()                # 1 request, at most once per 5 min
  return _filterStationsToBounds(cache.stations, bounds)
```

`_loadCatalogue()`:

1. GET `_balisesUrl`. Require 200 and a JSON array. Parse active beacons.
2. GET `_relevesUrl`. Require 200 and a JSON array. Parse readings.
3. Build stations from beacons and readings.
4. On success, replace the cache with both timestamps set to now.

The two requests are independent. Fetch them one after the other for simple
error handling. The extra round trip happens at most once per 24 hours.

If step 1 fails and a cache exists, keep the old cache and return. If step 2
fails, keep the new beacon list, build stations without wind, and set
`measurementsTimestamp` to the epoch so the next fetch retries the readings
without re-downloading the catalogue. Do not fail the whole layer because the
readings file is briefly unavailable.

`_refreshReleves()`:

1. GET `_relevesUrl`.
2. Parse readings, rebuild `stations` from `cache.beacons`, keep
   `beaconListTimestamp` and `bounds`.
3. Set `measurementsTimestamp` to now.

On failure, leave the cache untouched and log. The next viewport fetch retries
after the 5-minute TTL check, which still reads as expired.

`clearCache()` nulls both futures and the cache, as today.

`warmCache()` stays a world-bbox `fetchStations`, so the existing startup gate in
`main.dart` keeps working. The cost is one 237 KB + 33 KB load per cold start for
an enabled layer. This matches the current behaviour for keyed users. Disk
persistence is a future option, not part of this design.

`fetchWeatherData` is unchanged: the readings are already attached to each
station, so it extracts `windData` by station key. `getCacheStats` keeps its
existing keys and adds `beacons` and `readings_with_data`.

### 4.4 Parsing rules

`parseBeacon` (pure, testable):

- `idBalise` -> `toString()`. Skip when absent or empty.
- `latitude` and `longitude` -> `double`. Skip the beacon when either is absent
  (1 of 644 today).
- `en_maintenance` -> skip when `1` or `"1"`. Accept both so a schema change
  from integer to string cannot quietly re-enable 104 beacons in maintenance.
- `nom` -> nullable name. `departement` -> nullable string. `station_type` ->
  `'FFVL'` when absent.
- `altitude` -> nullable double.
- Never read `contact_*`, `remarques` or `alert_message`.

`parseReading` (pure, takes an explicit `now`):

- `idbalise` -> `toString()`.
- `date` -> `DateTime.tryParse(...).toUtc()`. No date means no reading.
- Require `vitesseVentMoy` and `directVentMoy`. A reading with only temperature
  is not a wind reading.
- `vitesseVentMax` -> nullable gust.
- Reject when `now.difference(date) > MapConstants.ffvlMeasurementMaxAge`.
- Return `WindData(speedKmh, gustsKmh, directionDegrees, timestamp)`.

`buildStations(beacons, readings)`:

- Join on the id string.
- Ignore readings with no matching beacon, and count them in the log.
- Build the display name with the existing department map: `name (Department
  name)` when the code maps to a department, `name (Dept <code>)` when it does
  not, and `name` when the field is absent.
- Keep the existing observation-type mapping: `OPENWINDMAP` ->
  `FFVL/OpenWindMap`, else `FFVL (<type>)`.
- `dataUrl` = `https://www.balisemeteo.com/balise.php?idBalise=<id>` (verified
  200). The old `url` field is gone. Keep the `www` prefix and the `e` in
  `balisemeteo`.

### 4.5 Reading age

`releves.json` holds one row per beacon and keeps the last row from an offline
station indefinitely. Without an age gate, a beacon that died months ago would
keep reporting its last wind as current.

Add:

```dart
// releves.json keeps the last reading of an offline beacon. Attach it only
// while it can still describe the wind a pilot would fly in.
static const Duration ffvlMeasurementMaxAge = Duration(hours: 2);
```

At the 2026-11-10 probe all 178 readings were younger than 2 hours, and 174 were
younger than 60 minutes. The gate removes dead beacons without dropping the
slow but live ones. The marker already shows the reading age, so the pilot keeps
the finer judgement.

### 4.6 Errors and logs

Keep the existing `FFVL_*` event names where they still describe the event:
`FFVL_REQUEST_START`, `FFVL_TIMEOUT`, `FFVL_HTTP_ERROR`, `FFVL_CACHE_HIT`,
`FFVL_BBOX_FILTER`, `FFVL_BBOX_NO_OVERLAP`, `FFVL_NO_STATIONS_IN_VIEW`,
`FFVL_WEATHER_EXTRACTED`.

Add:

| Event | Fields |
|---|---|
| `FFVL_CATALOGUE_LOADED` | `beacons`, `active`, `maintenance`, `readings`, `joined`, `stale`, `orphans`, `ms` |
| `FFVL_RELEVES_REFRESHED` | `readings`, `joined`, `stale`, `orphans`, `ms` |
| `FFVL_RELEVES_REFRESH_FAILED` | `error_type`, `message` |
| `FFVL_RESOURCE_GONE` | `resource`, `status`, `url` |

`FFVL_RESOURCE_GONE` is the signal that a resource id changed. Its log message
names the dataset page and the Discord channel.

Timeouts stay at 30 seconds. The `User-Agent: TheParaglidingApp/1.0` header
stays, and the app sends `Accept: application/json`.

## 5. Coverage and map behaviour

At the 2026-11-10 probe:

| Station type | Active | With reading |
|---|---:|---:|
| OPENWINDMAP | 335 | 0 |
| ADISON | 135 | 114 |
| HOLFUY | 26 | 25 |
| AUTRE | 12 | 6 |
| SENCROP | 11 | 11 |
| CTIC | 7 | 5 |
| METEOCONCEPT | 6 | 6 |
| EUCLIDE | 3 | 1 |
| IWEATHAR_PULL | 2 | 2 |
| GREEN_CITIZEN | 1 | 0 |
| PETIT_BALLON | 1 | 1 |
| WINDGURU | 1 | 0 |
| **Total** | **540** | **171** |

Two facts follow:

- **83% of the non-OpenWindMap beacons have a reading.** The FFVL layer remains
  useful for its own network.
- **OpenWindMap beacons have no reading in this dataset.** That is documented
  upstream: their readings are published by openwindmap.org. The app already
  loads those stations through the Pioupiou layer, and `WeatherStationService`
  deduplicates within 150 m, preferring the station with the newer reading
  (`weather_station_service.dart:329`). With the default settings the Pioupiou
  copy wins and the map shows one marker with wind.

The FFVL layer therefore stays a full catalogue, not a readings feed. A beacon
without a reading is a known launch with no current wind, which the existing
marker already renders as "No wind data". At zoom 10 or higher the viewport
holds only a handful of stations, so the empty markers are not a clutter
problem.

The Holfuy beacons in the catalogue (26 active, 25 with readings) also appear in
the Holfuy layer. The FFVL copy wins the deduplication because it has wind, so
tapping one opens the balisemeteo page rather than the on-tap Holfuy flow. That
is a small change in the link, not in the marker.

## 6. Key removal

The source is keyless. Leaving the key plumbing in place would keep a dead
secret in CI and a misleading "no FFVL key" warning at startup.

Remove `ApiKeys.ffvlApiKey` and update:

| File | Change |
|---|---|
| `the_paragliding_app/lib/services/api_keys.dart` | Remove the constant, its doc example, the `_anyKeyConfigured` term and the startup warning. |
| `the_paragliding_app/lib/main.dart` | Update the warm-up comment that names a missing FFVL key. |
| `the_paragliding_app/env.example.json` | Remove `FFVL_API_KEY`. |
| `the_paragliding_app/env.json` | Developer-local and gitignored. Remove the line locally, do not commit. |
| `.github/workflows/build.yml` | Remove the secret env entry and the two `--dart-define` lines. |
| `scripts/setup-google-play.sh` | Remove the prompt and the secret upload. |
| `GOOGLE_PLAY_DEPLOYMENT.md` | Remove the secret from the list. |
| `README_API_KEYS.md` | Remove the FFVL section and table row. |
| `the_paragliding_app/lib/presentation/screens/nearby_sites_screen.dart` | Update the "default: true, has API key" comment. |

After the release, delete the `FFVL_API_KEY` repository secret by hand. Code
that stops reading a secret is enough to ship, but the secret must not stay in
GitHub.

`ApiKeys.logStatus` keeps reporting OpenAIP, Cesium and Weather Underground.

## 7. Attribution and licence

The Etalab 2.0 licence permits commercial reuse and requires credit. The app
must name the source and the licence.

- Provider: `attributionName` = `FFVL (data.gouv.fr)`, `attributionUrl` = the
  dataset page. The marker's "Data: ..." line uses `attributionName`.
- About screen: change the FFVL link text to
  `FFVL weather beacons (data.gouv.fr)` and add a second compact link,
  `Licence Ouverte 2.0 (Etalab)`, to
  `https://www.etalab.gouv.fr/licence-ouverte-open-licence`. Put it in a
  `Padding(left: 28, top: 4)` with `Icons.copyright`, like the existing
  guide-licence lines (`about_screen.dart:269`).
- The station marker keeps linking to the balisemeteo page for the beacon.
- Etalab 2.0 also asks for the date of the last update. The marker's age chip
  shows the reading age, and the About link opens the dataset page, which states
  the dataset's last update.

## 8. Testing

### 8.1 Unit tests

Follow the Holfuy pattern: a `http.Client` field with a `httpClientForTest`
setter, `MockClient` from `package:http/testing`, and pure static parsers.
Parsers take an explicit `now` so age tests do not depend on the wall clock.

New file: `the_paragliding_app/test/ffvl_weather_provider_test.dart`.

Fixtures are short inline excerpts of the real files: five beacons (one ADISON
with a reading, one OPENWINDMAP without, one in maintenance as an integer, one in
maintenance as a string, one without a position) and four readings (good, missing
direction, old, orphan).

Cases:

1. Joins by id and reports km/h, degrees and gusts unchanged.
2. Parses `2026-11-10T02:09:08+01:00` as `01:09:08Z`.
3. Skips `en_maintenance` for both `1` and `"1"`.
4. Skips a beacon with no latitude or longitude.
5. A beacon with no reading keeps `windData == null`.
6. A reading with no speed or no direction gives no wind, not zero wind.
7. A reading older than 2 hours is dropped.
8. An orphan reading is ignored and counted in the log.
9. `dataUrl` is the balisemeteo page for that id.
10. A full load issues exactly two requests. A 5-minute refresh issues exactly
    one, to `_relevesUrl`, and does not touch `_balisesUrl`. This is the guard
    for the 78 MB/day defect.
11. A failed reading refresh keeps the previous stations.
12. A second fetch within both TTLs issues no request.
13. An outside-France bbox issues no request once the cache exists.
14. `requiresApiKey` is false and `isConfigured()` is true.

Test 10 is the most valuable. It fails if someone later "simplifies" the refresh
back to a full fetch.

### 8.2 Live contract test

Add a `network`-tagged test, `the_paragliding_app/test/ffvl_data_gouv_network_test.dart`.
The weekly `Live services` workflow (`network.yml`) already runs every
`network` test, so no workflow change is needed to run it.

Assertions:

- Both resource URLs return 200 after the redirect and a JSON array.
- `balises.json` has more than 500 entries.
- At least 99% of beacons have `idBalise`, `nom`, `latitude` and `longitude`.
- `releves.json` has more than 100 entries.
- At least 99% of readings have `idbalise` and a parseable `date`.
- At least one reading joins to a beacon.
- At least 90% of readings are younger than 2 hours. A sudden drop means the
  publish cadence or the file changed.

This test is the early warning for the next upstream schema change. It runs
weekly, not on every pull request. Add FFVL to the list at the top of
`network.yml`, which says what the schedule guards.

## 9. Documentation updates

Do these in the same change as the code:

- `docs/WEATHER_STATION_SOURCES.md`: FFVL row becomes "None" for API key. Update
  the "about 650 beacons" line and add that OpenWindMap readings arrive through
  the Pioupiou layer.
- `docs/api/WEATHER_STATIONS.md`: replace both endpoints, the key table row, the
  TTL table row and the "FFVL Beacons - Global Fetch-All" section. Add the
  two-file split and the 30-day static-cache trap.
- `README_API_KEYS.md`, `GOOGLE_PLAY_DEPLOYMENT.md`, `.github/workflows/build.yml`,
  `scripts/setup-google-play.sh`.
- `docs/README.md`: add this design under Developer References.
- Code comments that name `data.ffvl.fr`: `weather_station_source.dart`,
  `map_constants.dart`, `main.dart`, `nearby_sites_screen.dart`.

The old documentation at `docs/api/WEATHER_STATIONS.md:126` shows the keyed
endpoints. It must not survive the change.

## 10. Failure modes and monitoring

| Failure | Behaviour |
|---|---|
| Resource id changed (404/410) | Log `FFVL_RESOURCE_GONE`, keep the cache, show nothing new. Update the two constants and ship a patch. |
| `static.data.gouv.fr` 5xx or CDN outage | Keep the cache. Retry on the next viewport fetch. |
| Schema drift (field renamed) | The affected field becomes absent. Beacons still parse if id and position exist. Readings drop to no wind. The weekly test catches the drift. |
| `releves.json` briefly unavailable | Beacon list loads, stations show without wind, readings retry after the next TTL check. |
| Device clock wrong | Reading age can reject everything (slow clock) or accept everything (fast clock). No special handling. The marker's age chip shows the reading age. |
| Data volume | 237 KB once per 24 h plus 33 KB every 5 min while the map is open, about 10 MB/day. The CDN serves it, so the load is not a per-user API cost. |

Monitoring surface: the weekly live-services job, the `FFVL_*` logs, and the
FFVL Dev Discord server (`https://discord.gg/4sAFSm4TWG`) for announcements.
The design agent could not read Discord message history (login required). A
human should check the pinned posts for a deprecation date, a schema note or a
new resource id before the implementation starts.

## 11. Rollout

One pull request, no database migration and no preference migration.

Behaviour changes to expect:

- The layer becomes available to every install without a key. Users who
  previously saw no FFVL markers now see them, and the startup warm-up downloads
  the catalogue for them.
- Stations without a current reading are more visible than before, because the
  old embedded fallback is gone.
- The FFVL copy of a Holfuy station usually wins deduplication because it has
  wind, so the marker link changes from the Holfuy page to balisemeteo. The
  FFVL copy of an OpenWindMap station loses to the Pioupiou copy.

Rollback is a revert of the provider. The old keyed API is not a safe fallback:
the FFVL moved the source, and the key may be retired. If the new source fails
in the field, disable the layer through the filter while a patch ships.

## 12. Non-goals

- No disk persistence of the beacon catalogue. The 237 KB per cold start is
  accepted for now.
- No conditional GET. `releves.json` changes every 5 minutes, so a 5-minute poll
  almost always has new bytes.
- No per-bbox API. data.gouv.fr publishes whole files only.
- No OpenWindMap fetching inside the FFVL provider. The Pioupiou layer exists.
- No use of the other two FFVL datasets (`terrains.json`, `structures.json`).
- No historical readings. The file holds one row per beacon.
- No "maintenance" badge. Maintenance beacons stay hidden, as today.
- No substitution of `directVentInst` for the average direction.

## 13. Open questions

1. **Show beacons with no reading?** Recommended: yes, keep the full catalogue.
   The alternative hides 369 of 540 markers and makes the layer look smaller
   than the FFVL network.
2. **Is 2 hours the right reading age?** Recommended: yes. It keeps every live
   station in the probe and drops dead ones. A 90-minute gate would drop no
   current reading, so the choice only affects stations that are already
   offline. A 60-minute gate would drop about 2%.
3. **Keep the startup warm-up?** Recommended: yes, for consistency with
   Pioupiou. The alternative is a first-map-open delay in exchange for 270 KB
   less data per cold start.
4. **Station link target: balisemeteo.com or spotair.mobi?** Recommended:
   balisemeteo.com, which is the existing link and returned 200 for a live
   beacon.

## 14. File map

| File | Change |
|---|---|
| `the_paragliding_app/lib/services/weather_providers/ffvl_weather_provider.dart` | Rewrite transport, split catalogue and reading fetches, new parsers, no key, max age. |
| `the_paragliding_app/lib/utils/map_constants.dart` | Add `ffvlMeasurementMaxAge`. Update the FFVL TTL comments. |
| `the_paragliding_app/lib/services/api_keys.dart` | Remove `ffvlApiKey` and the startup warning. |
| `the_paragliding_app/lib/main.dart` | Update the warm-up comment. |
| `the_paragliding_app/lib/data/models/weather_station_source.dart` | Update the source comment. |
| `the_paragliding_app/lib/presentation/screens/about_screen.dart` | New attribution text and the licence link. |
| `the_paragliding_app/lib/presentation/screens/nearby_sites_screen.dart` | Update the comment on the default state. |
| `the_paragliding_app/test/ffvl_weather_provider_test.dart` | New unit tests. |
| `the_paragliding_app/test/ffvl_data_gouv_network_test.dart` | New `network` contract test. |
| `.github/workflows/build.yml` | Remove the FFVL secret. |
| `scripts/setup-google-play.sh` | Remove the FFVL secret prompt. |
| `the_paragliding_app/env.example.json` | Remove the key. |
| `README_API_KEYS.md`, `GOOGLE_PLAY_DEPLOYMENT.md` | Remove the key. |
| `docs/WEATHER_STATION_SOURCES.md`, `docs/api/WEATHER_STATIONS.md`, `docs/README.md` | Document the new source. |

## 15. Definition of done

- `flutter analyze` is clean.
- The unit tests pass, including the two-request/one-request refresh guard.
- `flutter test --tags network --run-skipped test/ffvl_data_gouv_network_test.dart`
  passes against the live files.
- On a Linux desktop run, opening the map over France logs
  `FFVL_CATALOGUE_LOADED` once, then `FFVL_RELEVES_REFRESHED` after 5 minutes,
  with no second beacon-list download.
- Markers show wind for ADISON beacons and no wind for OpenWindMap beacons.
- About shows the FFVL data.gouv.fr link and the Licence Ouverte 2.0 line.
- No FFVL key is needed in `env.json` or CI.
