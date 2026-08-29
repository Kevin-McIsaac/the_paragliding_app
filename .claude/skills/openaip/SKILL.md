---
name: openaip
description: Work with OpenAIP data in this app - airspace overlays and the OpenAIP map tile layer. Use when touching AirspaceCountryService, AirspaceGeoJsonService, AirspaceOverlayManager or OpenAipService, when airspace polygons are missing from the map, or when the OpenAIP tile layer fails to load. Covers the two separate paths (keyless bulk airspace bucket vs API-keyed tiles), the July-2026 bucket migration, and the airspace type/altitude encoding.
---

# OpenAIP integration

There are exactly **two** OpenAIP paths in this app, and confusing them has cost real
debugging time.

| what | where from | needs API key? | code |
|---|---|---|---|
| Airspace polygons | daily per-country export bucket | **no** | `AirspaceCountryService` |
| Base map "openaip" tile layer | `api.tiles.openaip.net` | **yes** | `OpenAipService` |

**There is no REST data API in use.** The app does not call `api.core.openaip.net`
anywhere. If you are looking for airports, navaids or reporting points — they are not
implemented; no service fetches them.

> Both CLAUDE.md and an earlier version of this skill described an `AviationDataService`
> fetching `/airports`, `/navaids` and `/reporting-points` from `api.core.openaip.net`,
> with `[AIRPORTS_API_REQUEST]` log tags. None of that exists in `lib/` — no such class,
> no such call, no such tag. Treat it as a design that was documented and never built.

## Airspace: the bucket

`AirspaceCountryService` bulk-downloads one GeoJSON per country, stores it in the local
database, and reads it back by bounding box.

```
https://storage.openaip.net/openaip-system-exports/<cc>_asp.geojson   # e.g. au_asp.geojson
```

`airspace_country_service.dart:38`. **When airspace breaks, check the bucket, not the
key** — airspace failing while the base map renders fine looks like an API-key problem
and is not one.

**The bucket moved in July 2026.** The old Google Cloud Storage bucket
(`storage.googleapis.com/29f98e10-...`) was switched to *Requester Pays* on ~2026-07-23
after OpenAIP was billed four-figure egress costs, and now returns `HTTP 400
UserProjectMissing` to every anonymous request — see openAIP/openaip#468 and #469. The S3
endpoint above is the sanctioned replacement, rate limited to 20 req/s.

- **Do not fetch airspace per viewport.** A viewport query is ~250 KiB and fires on every
  pan/zoom; that is the usage pattern that got the previous bucket locked down. One
  country is one request.
- The endpoint returns `content-encoding: utf-8`, which is a charset, not an encoding.
  Dart ignores it (only gzip is auto-uncompressed) so the app is fine, but `curl
  --compressed` fails on it — use plain `curl` when reproducing by hand.
- Per-country ETag / Last-Modified / download time are cached under
  `airspace_fetch_info_<CC>`; the request timeout is 2 minutes because the files are large.

`test/airspace_country_source_test.dart` guards the URL and, under the `network` tag,
that the bucket still serves usable GeoJSON.

## Tiles: the API key

```
https://{s}.api.tiles.openaip.net/api/data/{layer}/{z}/{x}/{y}.png?apiKey=...
```

`OpenAipService` owns the tile URL template, key storage (`openaip_api_key` in
SharedPreferences, falling back to `api_keys.dart`), and the airspace-overlay enable flag.
As of May 2023 OpenAIP consolidated everything into a single `openaip` layer.

`isAirspaceEnabled()` is the **single source of truth** for whether the overlay draws. The
Sites screen used to keep a second copy under its own key that defaulted to `true` while
this one defaulted to `false`, so a fresh install showed a ticked "Airspace" box over a
map that drew none. It deliberately does not write on read — persisting the default at
read time is what made that bug outlive a change of default.

## Airspace type and altitude encoding

The GeoJSON carries numeric codes, not the abbreviations shown in the UI. Mapping rules,
the full CTR/TMA/CTA/DANGER/RESTRICTED type list, and the altitude conversions live in
[docs/api/OPENAIP_API_STRUCTURE.md](../../../docs/api/OPENAIP_API_STRUCTURE.md).

Two rules worth repeating: flight levels (`unit=6`) are hundreds of feet (FL125 =
12,500 ft) while `unit=1` is feet directly; and ground reference (`referenceDatum=0`)
with `value=0` displays as `GND`.

## Troubleshooting

| Issue | Cause | Solution |
|---|---|---|
| Airspace missing, base map fine | The bucket, not the key | Check the export URL and `[AIRSPACE]` log lines |
| Airspace box ticked but nothing drawn | The old duplicate preference | `isAirspaceEnabled()` is the only flag; check reconciliation |
| Tiles blank / 401 | Missing or invalid API key | `[API_KEYS_STATUS]` at startup; key is for **tiles** only |
| `curl --compressed` fails on the export | Bogus `content-encoding: utf-8` | Use plain `curl` |

Log tags actually emitted: `[AIRSPACE]`, `[AIRSPACE_DB_INIT]`, `[AIRSPACE_FETCH_START]`.
