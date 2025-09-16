# Unified Loading Flow Sequence - Map Tiles, Sites & Airspaces

## Complete Loading Sequence Timeline

When a user pans/zooms the map, here's the precise sequence of events:

```
TIME    EVENT                           SYSTEM              ACTION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
0ms     User starts panning            UI Thread           Gesture detected
        ↓
5ms     Map camera moves               Flutter Map         Update viewport
        ↓
10ms    Calculate visible tiles        Flutter Map         Determine z/x/y tiles needed
        ↓
15ms    Request missing tiles          TileProvider        Check ImageCache → Network
        ├── Cache hits (immediate)     ←
        └── Cache misses (async) →     NetworkProvider     HTTP GET tile images
        ↓
20ms    Trigger map event              MapController       MapEventMove
        ↓
25ms    Cancel previous debouncer      MapWidget           _mapUpdateDebouncer?.cancel()
        ↓
30ms    Start new debounce timer       MapWidget           Timer(750ms, _loadVisibleData)
        ↓
50ms    [Tiles start arriving]         NetworkProvider     Display as received
        ↓
200ms   User stops panning             UI Thread           MapEventMoveEnd fired
        ↓
205ms   Cancel & restart debouncer    MapWidget           Reset 750ms timer
        ↓
[User continues panning/zooming - timer keeps resetting]
        ↓
955ms   User idle for 750ms           Timer               Debounce period expires
        ↓
960ms   _loadVisibleData() called      MapWidget           Unified data loading starts
        ↓
965ms   Check MapController ready      MapWidget           _isMapReady() validation
        ↓
970ms   Get current bounds             MapController       camera.visibleBounds
        ↓
975ms   Check bounds threshold         MapWidget           Compare with _lastProcessedBounds
        ↓                                                      (skip if change < 0.001°)
980ms   Update last bounds             MapWidget           Store for next comparison
        ↓
985ms   Parallel data fetch begins     Future.wait()       Launch simultaneous requests
        ├── _loadSitesForBounds() →
        │   ├── Check sites enabled    MapWidget           User preference check
        │   ├── Notify parent          Callback            onBoundsChanged
        │   ├── DB query               DatabaseService     Local sites in bounds
        │   └── API query              ParaglidingEarth    External sites (max 50)
        └── _loadAirspaceLayers() →
            ├── Check airspace enabled OpenAipService      User preference check
            ├── Check cache            AirspaceManager     Bounds key lookup
            └── API query              AirspaceGeoJson     OpenAIP /api/airspaces
        ↓
1200ms  Sites data returns             Parent Screen       Process & merge results
        ├── Match local/API sites
        ├── Track flight status
        └── Update state               setState()          Trigger UI rebuild
        ↓
1400ms  Airspace data returns          AirspaceService     Process GeoJSON
        ├── Filter by preferences
        ├── Filter by altitude
        ├── Clip polygons if needed
        └── Convert to Flutter polygons
        ↓
1450ms  Update UI layers               MapWidget.build()   Render all layers
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Detailed Request Examples

### 1. Map Tile Request (Immediate, No Debouncing)
```http
GET https://tile.openstreetmap.org/10/512/341.png
Headers:
  User-Agent: FreeFlightLog/1.0
  Cache-Control: max-age=86400

Response: 200 OK
Content-Type: image/png
Content-Length: 24576
[Binary PNG data]
```

### 2. Sites Request (After 750ms Debounce)
```http
GET https://api.paraglidingearth.com/sites/bounds
  ?north=47.5&south=47.0&east=8.5&west=8.0&limit=50
Headers:
  Accept: application/json

Response: 200 OK
[
  {
    "id": 1234,
    "name": "Interlaken",
    "latitude": 47.123,
    "longitude": 8.234,
    "altitude": 1250
  },
  ...
]
```

### 3. Airspace Request (After 750ms Debounce, Parallel with Sites)
```http
GET https://api.core.openaip.net/api/airspaces
  ?bbox=8.0,47.0,8.5,47.5&apiKey=xxx
Headers:
  Accept: application/json
  User-Agent: FreeFlightLog/1.0

Response: 200 OK
{
  "type": "FeatureCollection",
  "features": [
    {
      "_id": "abc123",
      "geometry": {
        "type": "Polygon",
        "coordinates": [[[8.1, 47.1], [8.2, 47.1], ...]]
      },
      "properties": {
        "type": 5,
        "icaoClass": "D",
        "name": "CTR Bern"
      }
    }
  ]
}
```

## Key Timing Characteristics

### Immediate Loading (No Delay)
- **Map Tiles**: Load as soon as needed
  - Network requests start within 15ms of pan/zoom
  - Cached tiles display in <10ms
  - New tiles appear as they arrive (50-200ms)

### Debounced Loading (750ms Delay)
- **Sites & Airspace**: Wait for user to stop moving
  - Timer starts on first movement
  - Resets with each movement
  - Loads only after 750ms of inactivity
  - Both load in parallel via `Future.wait()`

## Visual Timeline
```
User Action:  pan─────────pan───stop──────────────────────────────►
              │           │     │
Tiles:        ├─request──►├─req►│─────────────────────────────────►
              │ display◄──┤disp◄│
              │           │     │
Debounce:     ├─[750ms]──X     ├─[750ms]──────────────┐
              │                 │                      │
Sites:        │                 │                      ├─API call─►
              │                 │                      │  ◄─data──┤
              │                 │                      │
Airspace:     │                 │                      ├─API call─►
              │                 │                      │  ◄─data──┤
              │                 │                      │
Time (ms):    0───────────200───955───────────────────1200──────1450
```

## Cache Behavior

### Tile Cache (Flutter ImageCache)
```
First View:  Network → Cache → Display
Repeat View: Cache → Display (no network)
Cache Key:   "https://tile.osm.org/10/512/341.png"
Eviction:    LRU when limit reached (1000 tiles/100MB)
```

### Sites Cache (Geographic Bounds)
```
First View:  API → Process → Cache → Display
Repeat View: Cache → Display (no API call)
Cache Key:   "47.5_47.0_8.5_8.0" (north_south_east_west)
Duration:    Session-based
```

### Airspace Cache (AirspaceOverlayManager)
```
First View:  API → Filter → Process → Cache → Display
Repeat View: Cache → Display (no API call)
Cache Key:   "47.5_47.0_8.5_8.0" (matching sites format)
Duration:    Session-based with bounds tracking
```

## Performance Impact

### Network Requests per Pan/Zoom
```
Typical Scenario (zoom 10, pan 1km):
- Map Tiles: 15-25 requests (immediate)
- Sites: 1 request (after 750ms idle)
- Airspace: 1 request (after 750ms idle)
- Total: 17-27 requests

Before Unified Debouncing:
- Map Tiles: 15-25 requests
- Sites: 1 request (after 750ms)
- Airspace: 5-10 requests (every movement!)
- Total: 21-36 requests
```

### Data Transfer
```
Per View (typical):
- Tiles: 300-500KB (15-25 tiles × 20KB average)
- Sites: 5-10KB (JSON, 50 sites max)
- Airspace: 20-100KB (GeoJSON, varies by area)
- Total: 325-610KB

Cached View:
- Tiles: 0KB (from ImageCache)
- Sites: 0KB (from bounds cache)
- Airspace: 0KB (from bounds cache)
- Total: 0KB (fully cached)
```

## Error Handling & Recovery

### Failed Tile Load
```
15ms:   Request tile z10/x512/y341
200ms:  NetworkException
201ms:  ErrorTileCallback triggered
202ms:  Log error, show placeholder
5min:   Retry on next pan to area
```

### Failed Sites Load
```
960ms:  _loadSitesForBounds() starts
1200ms: API timeout/error
1201ms: Log error
1202ms: Show cached data if available
1203ms: Display empty state if no cache
Next:   Retry on next bounds change > threshold
```

### Failed Airspace Load
```
960ms:  _loadAirspaceLayers() starts
1400ms: API error (401, 500, timeout)
1401ms: Log structured error
1402ms: Continue without airspace layer
1403ms: User sees map + sites only
Next:   Retry on next bounds change
```

## Summary

The unified loading sequence demonstrates three distinct patterns:

1. **Instant Tiles**: No debouncing, immediate network requests, provides responsive map
2. **Debounced Sites**: 750ms wait, efficient API usage, bulk loading for visible area
3. **Debounced Airspace**: Same 750ms wait, parallel with sites, significant API reduction

This architecture balances user experience (instant map feedback) with API efficiency (debounced data layers), resulting in a responsive interface that minimizes unnecessary network requests.