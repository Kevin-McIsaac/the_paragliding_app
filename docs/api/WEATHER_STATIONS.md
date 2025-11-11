# Weather Station APIs

## Overview

The Paragliding App integrates with multiple weather station providers to display real-time wind data on the map. Each provider has different API capabilities, coverage areas, and data retrieval strategies.

## Provider Comparison

| Provider | Coverage | API Key | bbox Support | Strategy | Update Frequency |
|----------|----------|---------|--------------|----------|------------------|
| Aviation Weather Center | Global airports | No | ✅ Yes | Direct bbox query | Varies (1-60min) |
| Bureau of Meteorology (BOM) | Australia | No | ❌ No | State-based fetch | 10 minutes |
| FFVL Beacons | France/Europe | Yes | ❌ No | Global fetch-all | 5 minutes |
| Pioupiou (OpenWindMap) | Global | No | ❌ No | Global fetch-all | 20 minutes |
| NWS Observations | US only | No | ❌ No | Grid-based lookup | 10 minutes |

## Bounding Box Support

### ✅ Providers with Direct bbox Support

#### Aviation Weather Center (METAR)

**Implementation**: `aviation_weather_center_provider.dart:159`

```dart
final url = Uri.parse(
  'https://aviationweather.gov/api/data/metar?bbox=$bbox&format=json',
);
```

**bbox Format**: `minLat,minLon,maxLat,maxLon`

**Benefits**:
- Server-side filtering reduces bandwidth
- Fast response times for small regions
- Scales well with any map view size

**Example Request**:
```
https://aviationweather.gov/api/data/metar?bbox=45.50,-73.60,45.60,-73.50&format=json
```

### ❌ Providers Without bbox Support

These providers use alternative strategies with client-side filtering.

#### 1. Bureau of Meteorology (BOM) - State-Based Fetching

**Implementation**: `bom_weather_provider.dart:66`

**Strategy**:
- Australia divided into 7 states/territories
- Each state has separate XML file (~180-480 KB)
- Fetches only states that overlap with map view
- Filters cached data to bbox in-memory

**Code Reference**:
```dart
// Determine overlapping states
final overlappingStates = _determineOverlappingStates(bounds);

// Fetch each state in parallel
final futures = overlappingStates.map((state) => _fetchStateStations(state, bounds));
final results = await Future.wait(futures);

// In-memory filtering (line 488-504)
final filtered = stations.where((station) {
  return bounds.contains(LatLng(station.latitude, station.longitude));
}).toList();
```

**Coverage Areas**:
- WA (Western Australia) - Product ID: IDW60920
- NT (Northern Territory) - Product ID: IDD60920
- SA (South Australia) - Product ID: IDS60920
- QLD (Queensland) - Product ID: IDQ60920
- NSW (New South Wales) - Product ID: IDN60920
- VIC (Victoria) - Product ID: IDV60920
- TAS (Tasmania) - Product ID: IDT60920

**Caching Strategy**:
- Station list: 24 hours (locations don't change)
- Observations: 10 minutes (BOM updates every 10 min)
- Per-state caching enables instant pan/zoom within state

**Performance**:
- Initial fetch: ~180-480 KB per state
- Subsequent views in same state: Instant (in-memory filter)
- Multiple states visible: Parallel fetching

#### 2. FFVL Beacons - Global Fetch-All

**Implementation**: `ffvl_weather_provider.dart:208`

**Strategy**:
- Fetches ALL beacons globally (~650 beacons)
- Two API endpoints: beacon list + measurements
- Calculates bbox from returned stations
- Filters cached data to bbox in-memory
- Early exit if cached bbox doesn't overlap with view

**Code Reference**:
```dart
// Fetch all beacons
final beaconListUrl = Uri.parse(
  '$_baseUrl?base=balises&r=list&mode=json&key=$apiKey',
);

// Calculate bbox from stations (line 706-729)
final cachedBounds = _calculateBoundsFromStations(stations);

// Early exit optimization (line 66-76)
if (_globalCache != null && !_globalCache!.beaconListExpired) {
  if (!_boundsOverlap(bounds, _globalCache!.bounds)) {
    return []; // Skip this provider - no overlap
  }
}

// In-memory filtering (line 688-704)
final filtered = stations.where((station) {
  return bounds.contains(LatLng(station.latitude, station.longitude));
}).toList();
```

**API Endpoints**:
- Beacon list: `https://data.ffvl.fr/api/?base=balises&r=list&mode=json`
- Measurements: `https://data.ffvl.fr/api/?base=balises&r=releves_meteo`

**Caching Strategy**:
- Beacon list: 24 hours (locations don't change)
- Measurements: 5 minutes (FFVL updates every minute)
- Global cache with calculated bbox for overlap detection

**Performance**:
- Initial fetch: ~650 beacons
- Subsequent views: Instant (in-memory filter)
- Smart overlap detection prevents unnecessary API calls

**Special Features**:
- Filters out beacons in maintenance (`en_maintenance == '1'`)
- French department name mapping for display
- Multiple station types: FFVL, PIOUPIOU, OPENWINDMAP

#### 3. Pioupiou (OpenWindMap) - Global Fetch-All

**Implementation**: `pioupiou_weather_provider.dart:199`

**Strategy**:
- Fetches ALL stations globally (~1000 stations)
- Single API endpoint with embedded measurements
- Calculates bbox from returned stations
- Filters cached data to bbox in-memory
- Early exit if cached bbox doesn't overlap with view

**Code Reference**:
```dart
// Fetch all stations
final url = Uri.parse('$_baseUrl/live-with-meta/all');

// Calculate bbox from stations (line 419-442)
final cachedBounds = _calculateBoundsFromStations(stations);

// Early exit optimization (line 66-76)
if (_globalCache != null && !_globalCache!.stationListExpired) {
  if (!_boundsOverlap(bounds, _globalCache!.bounds)) {
    return []; // Skip this provider - no overlap
  }
}

// In-memory filtering (line 401-416)
final filtered = stations.where((station) {
  return bounds.contains(LatLng(station.latitude, station.longitude));
}).toList();
```

**API Endpoint**:
- Base URL: `http://api.pioupiou.fr/v1/live-with-meta/all`
- Note: HTTP only (no HTTPS support)

**Caching Strategy**:
- Station list: 24 hours (locations don't change)
- Measurements: 20 minutes (wind data updates frequently)
- Global cache with calculated bbox for overlap detection

**Performance**:
- Initial fetch: ~1000 stations
- Subsequent views: Instant (in-memory filter)
- Smart overlap detection prevents unnecessary API calls

**Special Features**:
- Only returns online stations (`status.state == 'on'`)
- Wind data represents 4-minute averages before timestamp
- Wind speeds already in km/h (no conversion needed)

#### 4. NWS (National Weather Service) - Grid-Based Lookup

**Implementation**: `nws_weather_provider.dart:297`

**Strategy**:
- Uses center point of bbox for grid lookup
- Two-step API process:
  1. `/points/{lat},{lon}` → Returns grid stations URL
  2. Grid URL → Returns ~50 stations for that grid
- Caches stations with containing bbox
- Filters cached data to requested bbox in-memory

**Code Reference**:
```dart
// Calculate bbox center for grid lookup (line 218-220)
final centerLat = (requestedBounds.north + requestedBounds.south) / 2;
final centerLon = (requestedBounds.east + requestedBounds.west) / 2;

// Step 1: Get grid stations URL
final gridUrl = await _getGridStationsUrl(centerLat, centerLon);
// Returns: https://api.weather.gov/gridpoints/{office}/{x},{y}/stations

// Step 2: Fetch stations for grid
final allStations = await _fetchGridStations(gridUrl);

// Calculate containing bbox (line 646-665)
final containingBbox = _calculateContainingBbox(allStations);

// In-memory filtering (line 263-266)
final filtered = allStations.where((station) {
  return requestedBounds.contains(LatLng(station.latitude, station.longitude));
}).toList();
```

**Coverage Areas**:
```dart
// Continental US
'CONUS': [-125.0, 24.5, -66.9, 49.6]

// Alaska (split to handle International Date Line)
'Alaska_Main': [-180.0, 51.2, -130.0, 71.4]
'Alaska_West_Aleutians': [172.0, 51.2, 180.0, 71.4]

// Hawaii
'Hawaii': [-178.3, 18.9, -154.8, 28.4]

// Caribbean territories
'Puerto_Rico': [-67.9, 17.9, -65.2, 18.5]
'US_Virgin_Islands': [-65.1, 17.7, -64.6, 18.4]

// Pacific territories
'Guam', 'Northern_Mariana_Islands', 'American_Samoa'
```

**Caching Strategy**:
- Station list: 24 hours (stations don't move)
- Observations: 10 minutes (update frequency varies 1-60min)
- Per-grid caching with bbox containment checks
- Separate observation cache per station

**Performance**:
- Initial fetch: ~50 stations per grid
- Early exit for non-US locations (coverage check)
- Cache reuse when zooming/panning within same grid area
- Separate parallel fetching for observations

**Special Features**:
- Fast 404 detection for non-US locations
- Grid-based approach provides good station density
- Observation type inference from station ID
- Separate caching for station lists and observations

## Caching Architecture

### Dual-Timestamp Caching

Providers use separate TTLs for station lists vs. measurements:

```dart
class _CacheEntry {
  final List<WeatherStation> stations;
  final DateTime stationListTimestamp;    // 24-hour TTL
  final DateTime measurementsTimestamp;   // 5-20 minute TTL

  bool get stationListExpired { /* ... */ }
  bool get measurementsExpired { /* ... */ }
}
```

**Benefits**:
- Station locations cached for 24 hours (rarely change)
- Measurements refreshed frequently (5-20 minutes)
- Reduces API calls while maintaining fresh data

### Cache TTL Summary

| Provider | Station List TTL | Measurements TTL |
|----------|------------------|------------------|
| Aviation Weather Center | 1 hour | 1 hour |
| BOM | 24 hours | 10 minutes |
| FFVL | 24 hours | 5 minutes |
| Pioupiou | 24 hours | 20 minutes |
| NWS | 24 hours | 10 minutes |

## Performance Optimizations

### 1. Early Exit for Non-Overlapping Regions

Global providers (FFVL, Pioupiou) calculate bbox from cached stations and exit early if view doesn't overlap:

```dart
// Check if cached bbox overlaps with requested bounds
if (_globalCache != null && !_globalCache!.beaconListExpired) {
  if (!_boundsOverlap(bounds, _globalCache!.bounds)) {
    return []; // Skip this provider - no overlap with view
  }
}
```

### 2. Skip Measurement Refresh if No Stations in View

```dart
// Check if ANY stations exist in current view
final hasStationsInView = _globalCache!.stations.any((s) =>
  bounds.contains(LatLng(s.latitude, s.longitude))
);

if (!hasStationsInView) {
  return []; // Skip API call - no stations to show
}
```

### 3. Parallel Fetching

BOM fetches multiple states in parallel when they overlap with view:

```dart
final futures = overlappingStates.map((state) =>
  _fetchStateStations(state, bounds)
);
final results = await Future.wait(futures);
```

### 4. Request Deduplication

All providers prevent duplicate simultaneous requests:

```dart
if (_pendingRequests.containsKey(cacheKey)) {
  return _pendingRequests[cacheKey]!;
}

final future = _fetchFromApi();
_pendingRequests[cacheKey] = future;
try {
  return await future;
} finally {
  _pendingRequests.remove(cacheKey);
}
```

## Wind Data Format

All providers normalize wind data to a common format:

```dart
class WindData {
  final double speedKmh;           // Wind speed in km/h
  final double directionDegrees;   // 0-360, where 0 = North
  final double? gustsKmh;          // Peak gusts in km/h (optional)
  final double? precipitationMm;   // Rainfall (BOM only)
  final DateTime timestamp;        // Observation time (UTC)
}
```

### Unit Conversions

| Provider | Native Unit | Conversion |
|----------|-------------|------------|
| Aviation Weather Center | Knots | × 1.852 → km/h |
| BOM | km/h | No conversion |
| FFVL | km/h | No conversion |
| Pioupiou | km/h | No conversion |
| NWS | km/h | No conversion |

## API Authentication

| Provider | Requires API Key | Configuration |
|----------|------------------|---------------|
| Aviation Weather Center | No | N/A |
| BOM | No | N/A |
| FFVL | Yes | `ApiKeys.ffvlApiKey` |
| Pioupiou | No | N/A |
| NWS | No | N/A |

## Error Handling

### Non-Coverage Areas

Providers handle requests outside their coverage area gracefully:

**Aviation Weather Center**: Returns 204 No Content (empty list)
**BOM**: Returns empty list if no states overlap
**FFVL**: Early exit if cached bbox doesn't overlap
**Pioupiou**: Early exit if cached bbox doesn't overlap
**NWS**: Returns 404 from `/points` endpoint, cached as empty

### Timeout Handling

All providers use 30-second timeouts with structured logging:

```dart
final response = await http.get(url).timeout(
  const Duration(seconds: 30),
  onTimeout: () {
    LoggingService.structured('PROVIDER_TIMEOUT', {
      'duration_ms': stopwatch.elapsedMilliseconds,
    });
    return http.Response('{"error": "Request timeout"}', 408);
  },
);
```

## Implementation Files

| Provider | File Path |
|----------|-----------|
| Aviation Weather Center | `lib/services/weather_providers/aviation_weather_center_provider.dart` |
| BOM | `lib/services/weather_providers/bom_weather_provider.dart` |
| FFVL | `lib/services/weather_providers/ffvl_weather_provider.dart` |
| Pioupiou | `lib/services/weather_providers/pioupiou_weather_provider.dart` |
| NWS | `lib/services/weather_providers/nws_weather_provider.dart` |
| Base Interface | `lib/services/weather_providers/weather_station_provider.dart` |
| Registry | `lib/services/weather_providers/weather_station_provider_registry.dart` |

## Adding New Providers

To add a new weather station provider:

1. **Implement the interface** (`WeatherStationProvider`)
2. **Choose a caching strategy**:
   - **Has bbox API?** → Use Aviation Weather Center pattern
   - **Regional API?** → Use BOM state-based pattern
   - **Small global dataset?** → Use FFVL/Pioupiou fetch-all pattern
   - **Grid/point lookup?** → Use NWS grid-based pattern
3. **Handle coverage area** (return empty list outside coverage)
4. **Normalize wind data** (convert to km/h if needed)
5. **Add to registry** (`WeatherStationProviderRegistry`)
6. **Test caching** (station list + measurements)
7. **Verify performance** (logging with structured data)

## Best Practices

### Caching
- Cache station lists for 24 hours (locations are static)
- Cache measurements based on provider update frequency
- Calculate and store bbox for global providers
- Implement early exit for non-overlapping regions

### API Calls
- Always deduplicate simultaneous requests
- Use timeouts (30 seconds recommended)
- Handle 404/204 responses gracefully
- Log structured data for debugging

### Performance
- Filter in-memory after caching (don't re-fetch)
- Fetch multiple regions in parallel when applicable
- Skip measurement refresh if no stations in view
- Round bbox for reasonable cache granularity

### Error Handling
- Return empty list for non-coverage areas
- Log all API errors with structured logging
- Cache empty results to avoid repeated failures
- Gracefully handle malformed responses

## Related Documentation

- [BOM Weather Stations](BOM_WEATHER_STATIONS.md) - Detailed BOM implementation
- [OpenAIP API Structure](OPENAIP_API_STRUCTURE.md) - Aviation data (airspaces, not weather)
