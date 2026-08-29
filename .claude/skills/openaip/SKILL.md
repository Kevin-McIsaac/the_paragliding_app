---
name: openaip
description: Work with OpenAIP aviation-data overlays (airspace, airports, navaids, reporting points) in this app. Use when touching AirspaceGeoJsonService, AviationDataService, AirspaceOverlayManager, OpenAipService, or debugging airspace/airport/navaid data not showing on the map. Covers the two separate data paths (bulk airspace bucket vs authenticated API), endpoints, auth, and the July-2026 bucket migration.
---

# OpenAIP API integration

Aviation data overlays: airspaces, airports, navigation aids, reporting points.

## Two different data paths - do not confuse them

**Airspace overlays do not use the API and need no API key.** They are bulk-downloaded
per country from OpenAIP's public daily export bucket by `AirspaceCountryService`,
stored in the local database, and read back by bounding box. That is what makes airspace
work offline, which matters because launch sites usually have no signal.

```
https://storage.openaip.net/openaip-system-exports/<cc>_asp.geojson   # e.g. au_asp.geojson
```

The API below is used for the *other* layers (airports, navaids, reporting points) and
for OpenAIP tile URLs - those do need the key.

This distinction cost real debugging time: airspace was failing while the base map
rendered fine, which looked like an API-key problem and is not one. **When airspace
breaks, check the bucket, not the key.**

**The bucket moved in July 2026.** The old Google Cloud Storage bucket
(`storage.googleapis.com/29f98e10-...`) was switched to *Requester Pays* on ~2026-07-23
after OpenAIP was billed four-figure egress costs, and now returns `HTTP 400
UserProjectMissing` to every anonymous request - see openAIP/openaip#468 and #469. The
S3 endpoint above is the sanctioned replacement, rate limited to 20 req/s.

Two consequences worth keeping:

- **Do not fetch airspace per viewport.** A viewport query is ~250 KiB and fires on
  every pan/zoom; that is the usage pattern that got the previous bucket locked down.
  One country is one request.
- The endpoint returns `content-encoding: utf-8`, which is a charset, not an encoding.
  Dart ignores it (only gzip is auto-uncompressed) so the app is fine, but `curl
  --compressed` fails on it - use plain `curl` when reproducing by hand.

`test/airspace_country_source_test.dart` guards both the URL and, under the `network`
tag, that the bucket still serves usable GeoJSON.

## API endpoints & authentication

```
Base URL: https://api.core.openaip.net/api
Authentication: API key as query parameter (?apiKey=xxx)
```

**Working endpoints:**

- `/api/airspaces` - Controlled airspace polygons (CTR, TMA, CTA, danger areas, etc.)
- `/api/airports` - Airport point data with details and frequencies
- `/api/navaids` - Navigation aids (VOR, NDB, DME, waypoints)
- `/api/reporting-points` - VFR reporting points with altitude restrictions

```http
GET /api/{endpoint}?bbox=west,south,east,north&limit=500&apiKey={key}
Headers:
  Accept: application/json
  User-Agent: TheParaglidingApp/1.0
```

**Auth goes in the URL query parameter, not headers** - a common wrong-first-guess.

All endpoints return GeoJSON `FeatureCollection`:

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "_id": "unique_identifier",
      "geometry": { "type": "Point|Polygon", "coordinates": [...] },
      "properties": { "...": "endpoint-specific data" }
    }
  ]
}
```

## Code integration

- `AirspaceGeoJsonService` - airspace polygons and styling
- `AviationDataService` - airports, navaids, reporting points
- `AirspaceOverlayManager` - coordinates all aviation data layers
- `OpenAipService` - manages API keys and layer preferences

```dart
// Correct auth (URL parameter, not headers), individually cached per data type
final url = 'https://api.core.openaip.net/api/airports'
    '?bbox=$west,$south,$east,$north&limit=500&apiKey=$apiKey';
final airports = await AviationDataService.instance.fetchAirports(bounds);
```

## Visual representation

- **Airspaces**: semi-transparent polygons, type-specific colors
- **Airports**: circular markers with airplane icons, sized by category
- **Navaids**: symbol markers (⬡ VOR, ● NDB, ◇ DME, ◉ Waypoints)
- **Reporting points**: triangle markers with altitude-restriction tooltips

## Troubleshooting

| Issue | Cause | Solution |
|-------|--------|----------|
| 401 Auth Failed | Invalid API key | Check OpenAIP account, verify key |
| 404 Not Found | Wrong endpoint | Use full names: `/airports` not `/apt` |
| No data returned | Geographic bounds | Try different location/zoom level |
| Headers auth failure | Wrong auth method | Use query parameter, not headers |
| Airspace missing, base map fine | Bucket, not API key | Check the bucket URL above, not `OpenAipService` |

Structured logs for the API layer: `[AIRPORTS_API_REQUEST]` / `[AIRPORTS_API_SUCCESS]`
with `url`, `bounds`, `has_api_key`, `airports_count`, `cache_key`.
