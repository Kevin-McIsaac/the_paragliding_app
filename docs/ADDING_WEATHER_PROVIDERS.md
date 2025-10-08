# Adding Weather Station Providers

This guide explains how to add a new weather station data provider to Free Flight Log.

## Architecture Overview

The weather station system uses a **provider-based architecture** that allows multiple weather data sources to work together:

```
WeatherStationService
    ↓ (coordinates all providers)
WeatherStationProviderRegistry
    ↓ (manages available providers)
WeatherStationProvider (interface)
    ↓ (implemented by each source)
├─ MetarWeatherProvider
├─ NwsWeatherProvider
└─ YourNewProvider
```

## Core Components

### 1. WeatherStationSource Enum

**File:** `lib/data/models/weather_station_source.dart`

Add your provider identifier:

```dart
enum WeatherStationSource {
  metar,
  nws,
  yourProvider,  // Add here
}
```

### 2. WeatherStationProvider Interface

**File:** `lib/services/weather_providers/weather_station_provider.dart`

All providers must implement this interface:

```dart
abstract class WeatherStationProvider {
  // Identification
  WeatherStationSource get source;
  String get displayName;        // "Your Provider Name"
  String get description;        // Short description for UI
  String get attributionName;    // For About screen
  String get attributionUrl;     // Provider website

  // Configuration
  bool get requiresApiKey;
  Duration get cacheTTL;
  Future<bool> isConfigured();

  // Data fetching
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds);
  Future<Map<String, WindData>> fetchWeatherData(List<WeatherStation> stations);

  // Cache management
  void clearCache();
  Map<String, dynamic> getCacheStats();
}
```

### 3. Create Provider Implementation

**File:** `lib/services/weather_providers/your_provider_weather_provider.dart`

```dart
class YourProviderWeatherProvider implements WeatherStationProvider {
  static final YourProviderWeatherProvider instance = YourProviderWeatherProvider._();
  YourProviderWeatherProvider._();

  static const String _baseUrl = 'https://api.yourprovider.com';

  @override
  WeatherStationSource get source => WeatherStationSource.yourProvider;

  @override
  String get displayName => 'Your Provider';

  @override
  String get description => 'Description shown in UI';

  @override
  String get attributionName => 'Your Provider Inc.';

  @override
  String get attributionUrl => 'https://yourprovider.com/';

  @override
  Duration get cacheTTL => MapConstants.weatherStationCacheTTL;

  @override
  bool get requiresApiKey => true; // or false

  @override
  Future<bool> isConfigured() async {
    // Check if API key is configured (if required)
    return true;
  }

  @override
  Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
    // Fetch station list from API
    // Parse response
    // Return List<WeatherStation>
  }

  @override
  Future<Map<String, WindData>> fetchWeatherData(
    List<WeatherStation> stations,
  ) async {
    // Fetch weather observations for stations
    // Return Map<stationKey, WindData>
  }

  @override
  void clearCache() {
    // Clear any cached data
  }

  @override
  Map<String, dynamic> getCacheStats() {
    return {
      'total_cache_entries': 0,
      'valid_cache_entries': 0,
    };
  }
}
```

### 4. Register Provider

**File:** `lib/services/weather_providers/weather_station_provider.dart`

Add to the registry:

```dart
class WeatherStationProviderRegistry {
  static final Map<WeatherStationSource, WeatherStationProvider> _providers = {
    WeatherStationSource.metar: MetarWeatherProvider.instance,
    WeatherStationSource.nws: NwsWeatherProvider.instance,
    WeatherStationSource.yourProvider: YourProviderWeatherProvider.instance, // Add here
  };

  // ... rest of registry code
}
```

## Data Flow

### Station Fetching

```
1. User views map at zoom ≥ 10
2. WeatherStationService.getStationsInBounds() called
3. Service checks which providers are enabled (via SharedPreferences)
4. Service calls fetchStations() on each enabled provider in parallel
5. Results are combined and deduplicated
6. Stations displayed as markers on map
```

### Weather Data Fetching

```
1. WeatherStationService.getWeatherForStations() called
2. Stations grouped by source
3. Each provider's fetchWeatherData() called with its stations
4. Results combined into Map<stationKey, WindData>
5. Wind data displayed on markers
```

## UI Integration - Map Filter Dialog

### Adding Provider Checkbox to Filter Map Dialog

When adding a new provider, you **must** update both the dialog and parent screen to properly enable/disable it:

**Step 1: Add to `map_filter_dialog.dart`**

1. Add parameter to constructor:
```dart
const MapFilterDialog({
  required this.metarEnabled,
  required this.nwsEnabled,
  required this.yourProviderEnabled,  // Add here
  // ... other parameters
});
```

2. Add state variable:
```dart
class _MapFilterDialogState extends State<MapFilterDialog> {
  late bool _metarEnabled;
  late bool _nwsEnabled;
  late bool _yourProviderEnabled;  // Add here
```

3. Initialize in `initState()`:
```dart
_yourProviderEnabled = widget.yourProviderEnabled;
```

4. Add checkbox widget in weather providers section:
```dart
_buildProviderCheckbox(
  value: _yourProviderEnabled,
  label: 'Your Provider Name',
  subtitle: WeatherStationProviderRegistry.getProvider(
    WeatherStationSource.yourProvider
  ).description,
  onChanged: _weatherStationsEnabled ? (value) => setState(() {
    _yourProviderEnabled = value ?? true;
    _applyFiltersImmediately();
  }) : null,
),
```

5. Update `onApply` callback signature:
```dart
widget.onApply(
  _sitesEnabled,
  _airspaceEnabled,
  _forecastEnabled,
  _weatherStationsEnabled,
  _metarEnabled,
  _nwsEnabled,
  _yourProviderEnabled,  // Add here
  _airspaceTypes,
  _icaoClasses,
  _maxAltitudeFt,
  _clippingEnabled,
);
```

**Step 2: Update `nearby_sites_screen.dart`**

1. Add state variable:
```dart
bool _yourProviderEnabled = true;  // Default: true
```

2. Load from preferences in `initState()`:
```dart
final yourProviderEnabled = prefs.getBool(
  'weather_provider_${WeatherStationSource.yourProvider.name}_enabled'
) ?? true;
```

3. Set state in `initState()`:
```dart
_yourProviderEnabled = yourProviderEnabled;
```

4. Pass to dialog when opening:
```dart
_DraggableFilterDialog(
  metarEnabled: _metarEnabled,
  nwsEnabled: _nwsEnabled,
  yourProviderEnabled: _yourProviderEnabled,  // Add here
  // ... other parameters
)
```

5. Handle in `_handleFilterApply()`:
```dart
void _handleFilterApply(
  bool sitesEnabled,
  bool airspaceEnabled,
  bool forecastEnabled,
  bool weatherStationsEnabled,
  bool metarEnabled,
  bool nwsEnabled,
  bool yourProviderEnabled,  // Add here
  // ... other parameters
) async {
  // Track previous state
  final previousYourProviderEnabled = _yourProviderEnabled;

  // Update state
  setState(() {
    _yourProviderEnabled = yourProviderEnabled;
  });

  // Save to preferences
  await prefs.setBool(
    'weather_provider_${WeatherStationSource.yourProvider.name}_enabled',
    yourProviderEnabled
  );

  // Handle provider changes
  if (weatherStationsEnabled &&
      yourProviderEnabled != previousYourProviderEnabled) {
    WeatherStationService.instance.clearCache();
    _fetchWeatherStations();
  }
}
```

6. Update loading overlay to filter disabled providers:
```dart
...WeatherStationProviderRegistry.getAllSources()
    .where((source) {
      // Only show enabled providers in loading overlay
      if (source == WeatherStationSource.metar) return _metarEnabled;
      if (source == WeatherStationSource.nws) return _nwsEnabled;
      if (source == WeatherStationSource.yourProvider) return _yourProviderEnabled;
      return false;
    })
    .map((source) {
      // ... create MapLoadingItem
    })
```

**Step 3: Update `_DraggableFilterDialog` wrapper**

Add parameter to the wrapper widget in `nearby_sites_screen.dart`:

```dart
class _DraggableFilterDialog extends StatefulWidget {
  final bool yourProviderEnabled;  // Add here

  const _DraggableFilterDialog({
    required this.yourProviderEnabled,  // Add here
    // ... other parameters
  });
}
```

### Provider Enable/Disable Flow

1. **User toggles checkbox** → `_applyFiltersImmediately()` called
2. **State updated** → `_yourProviderEnabled` changes
3. **Saved to preferences** → `weather_provider_yourProvider_enabled` key
4. **Cache cleared** → If provider changed, all caches cleared
5. **Stations re-fetched** → `WeatherStationService.getStationsInBounds()` called
6. **Service reads preferences** → `_getEnabledProviders()` checks `yourProvider_enabled`
7. **Provider filtered** → Only enabled providers added to `enabledProviders` list
8. **API not called** → Disabled providers never enter fetch pipeline
9. **No loading indicator** → Disabled providers excluded from overlay filter
10. **No markers** → Disabled providers never appear on map

## Implementation Checklist

- [ ] Add enum value to `WeatherStationSource`
- [ ] Create provider implementation file
- [ ] Implement all `WeatherStationProvider` interface methods
- [ ] Add provider to `WeatherStationProviderRegistry`
- [ ] Add API endpoints/authentication if needed
- [ ] Implement proper caching (stations and weather data)
- [ ] Add structured logging for debugging
- [ ] Handle errors gracefully (timeouts, invalid responses)
- [ ] Add user agent header: `User-Agent: FreeFlightLog/1.0`
- [ ] Test with various bounding boxes and zoom levels
- [ ] Add attribution to About screen (automatic via `attributionName`/`attributionUrl`)
- [ ] Update preferences handling if API key required

## Example APIs to Consider

### Global Coverage

- **OpenWeatherMap** - Global, requires API key, paid tiers available
- **WeatherAPI.com** - Global, free tier available
- **Tomorrow.io** - Global, weather stations and observations

### Regional Coverage

- **DWD (Germany)** - Free, German weather service
- **Met Office (UK)** - Free, UK weather service
- **Météo-France** - Free, French weather service
- **BOM (Australia)** - Free, Australian weather service
- **MetService (NZ)** - Free, New Zealand weather service

### Aviation-Specific

- **CheckWX** - Global METAR/TAF aggregator, free tier
- **AWC Text Data Server** - US aviation weather text products

## Best Practices

### Performance

- Cache station lists (they rarely change)
- Batch weather data requests when possible
- Use connection pooling for multiple requests
- Implement request deduplication for concurrent calls
- Set reasonable timeouts (10-30 seconds)

### Error Handling

- Log all API errors with structured logging
- Return empty lists/maps on failure (don't crash)
- Handle rate limiting gracefully
- Provide user-friendly error messages

### Caching Strategy

Choose the appropriate strategy based on your provider's network size and API characteristics:

#### Strategy 1: Bbox-Based Caching (METAR, NWS)
**Best for: Large networks (1000s+ stations), bbox-based APIs**

```dart
// Cache key includes bounding box
final cacheKey = '${bounds.west.toStringAsFixed(1)},${bounds.south.toStringAsFixed(1)},'
                 '${bounds.east.toStringAsFixed(1)},${bounds.north.toStringAsFixed(1)}';

// Cache entry with timestamp
class _CacheEntry {
  final List<WeatherStation> stations;
  final DateTime timestamp;
  final LatLngBounds bounds;

  bool isExpired() =>
      DateTime.now().difference(timestamp) > MapConstants.weatherStationCacheTTL;
}

// LRU cache (Least Recently Used)
final LinkedHashMap<String, _CacheEntry> _cache = LinkedHashMap();
static const int _maxCacheSize = 20;  // Limit memory usage
```

**Advantages:**
- Minimal memory footprint (only caches visible areas)
- Fast for repeated pan/zoom in same region
- Works with bbox-based APIs

**Disadvantages:**
- Cache miss on every pan/zoom to new area
- Multiple API calls when exploring map

#### Strategy 2: Global Caching (Pioupiou/OpenWindMap)
**Best for: Small networks (<5000 stations), global APIs**

```dart
// Single global cache for ALL stations
class _GlobalCacheEntry {
  final List<WeatherStation> stations;
  final DateTime stationListTimestamp;    // 24hr TTL
  final DateTime measurementsTimestamp;   // 20min TTL

  bool get stationListExpired =>
      DateTime.now().difference(stationListTimestamp) >
      MapConstants.pioupiouStationListCacheTTL;  // 24 hours

  bool get measurementsExpired =>
      DateTime.now().difference(measurementsTimestamp) >
      MapConstants.pioupiouMeasurementsCacheTTL;  // 20 minutes
}

_GlobalCacheEntry? _globalCache;

Future<List<WeatherStation>> fetchStations(LatLngBounds bounds) async {
  // Check if station list cache is valid
  if (_globalCache != null && !_globalCache!.stationListExpired) {
    // Refresh measurements if stale
    if (_globalCache!.measurementsExpired) {
      await _refreshMeasurements();
    }
    // Filter in-memory to bbox
    return _filterStationsToBounds(_globalCache!.stations, bounds);
  }

  // Fetch all stations from API
  final stations = await _fetchAllStations();
  _globalCache = _GlobalCacheEntry(
    stations: stations,
    stationListTimestamp: DateTime.now(),
    measurementsTimestamp: DateTime.now(),
  );

  return _filterStationsToBounds(stations, bounds);
}
```

**Advantages:**
- Instant pan/zoom (in-memory bbox filter)
- Single API call for entire network
- Measurements refresh without re-fetching station list

**Disadvantages:**
- Higher memory usage (~1000 stations = ~500KB)
- Overkill for large networks (10000+ stations)

#### Dual-TTL Pattern (Pioupiou)

Separate TTLs for station locations vs. measurements:

```dart
// Station locations: Rarely change (24hr TTL)
static const Duration pioupiouStationListCacheTTL = Duration(hours: 24);

// Wind measurements: Update frequently (20min TTL)
static const Duration pioupiouMeasurementsCacheTTL = Duration(minutes: 20);

Future<void> _refreshMeasurements() async {
  final stations = await _fetchAllStations();
  if (stations.isNotEmpty && _globalCache != null) {
    // Keep original station list timestamp
    _globalCache = _GlobalCacheEntry(
      stations: stations,
      stationListTimestamp: _globalCache!.stationListTimestamp,  // Keep old
      measurementsTimestamp: DateTime.now(),  // Update new
    );
  }
}
```

### Caching Strategy Comparison

| Provider | Strategy | Network Size | Cache TTL | Memory Usage | API Calls/Hour |
|----------|----------|--------------|-----------|--------------|----------------|
| **METAR** | Bbox | ~10,000 stations | 30 min | Low (~100KB) | High (varies) |
| **NWS** | Bbox + Grid | ~2,000 stations | Station: 24hr<br>Obs: 10min | Medium (~200KB) | Medium (1-2) |
| **Pioupiou** | Global | ~1,000 stations | List: 24hr<br>Data: 20min | Medium (~500KB) | Low (1-3) |

### Recommended TTLs by Data Type

```dart
// Station metadata (lat/lon, name, ID) - Changes rarely
Duration.hours(24)     // Global networks (Pioupiou)
Duration.hours(1)      // Regional networks (NWS)
Duration.minutes(30)   // Large networks (METAR)

// Wind measurements - Updates frequently
Duration.minutes(5)    // Real-time critical
Duration.minutes(10)   // Standard updates (NWS)
Duration.minutes(20)   // Less frequent updates (Pioupiou)
Duration.minutes(30)   // Slow-updating networks (METAR)
```

### API Etiquette

- Always include `User-Agent: FreeFlightLog/1.0`
- Respect rate limits
- Cache aggressively to minimize requests
- Include attribution as required by terms of service
- Check API terms for commercial use restrictions

## Testing

1. **Enable provider** in Map Filter dialog
2. **Zoom in** to zoom level ≥ 10
3. **Verify stations appear** on map
4. **Check wind data** displays on markers
5. **Test cache** by moving map and returning
6. **Test with provider disabled** - markers should disappear
7. **Test error cases** - network timeout, invalid API key, etc.
8. **Check logs** for structured logging output

## Debugging

Enable debug logging in `LoggingService` to see:

- `[WEATHER_STATION_FETCH_START]` - Provider fetch initiated
- `[WEATHER_STATION_FETCH_COMPLETE]` - Station count by provider
- `[STATION_FETCH_SUCCESS]` - Total stations with data
- Provider-specific logs (e.g., `[METAR_API_REQUEST]`, `[NWS_OBSERVATION_SUCCESS]`)

## Configuration Storage

Provider settings are stored in `SharedPreferences`:

```dart
// Enable/disable provider
final key = 'weather_provider_${source.name}_enabled';
await prefs.setBool(key, enabled);

// API key (if required)
final apiKeyKey = 'weather_provider_${source.name}_api_key';
await prefs.setString(apiKeyKey, apiKey);
```

## Related Files

- **Core Interface:** `lib/services/weather_providers/weather_station_provider.dart`
- **Service Coordinator:** `lib/services/weather_station_service.dart`
- **Data Models:** `lib/data/models/weather_station.dart`, `lib/data/models/wind_data.dart`
- **UI Integration:** `lib/presentation/widgets/map_filter_dialog.dart`
- **Map Display:** `lib/presentation/widgets/weather_station_marker.dart`
- **Examples:** `lib/services/weather_providers/metar_weather_provider.dart`, `lib/services/weather_providers/nws_weather_provider.dart`

## Support

For questions or issues, check:

- [Technical Design Document](TECHNICAL_DESIGN.md)
- [Functional Specification](FUNCTIONAL_SPECIFICATION.md)
- Existing provider implementations for reference


## Testing API Endpoints

### METAR (Aviation Weather Center)

Get observations for a specific station:

```bash
curl -s "https://aviationweather.gov/api/data/metar?ids=KSNS&format=json" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

Get observations for multiple stations:

```bash
curl -s "https://aviationweather.gov/api/data/metar?ids=KSNS,KSFO,KOAK&format=json" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

Get observations in a bounding box:

```bash
# Format: bbox=south,west,north,east
curl -s "https://aviationweather.gov/api/data/metar?bbox=36.5,-122,37,-121&format=json" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

**Response format:** JSON array with wind speed in knots (`wspd`), direction in degrees (`wdir`)

### NWS (National Weather Service)

Get station metadata:
```bash
curl -s "https://api.weather.gov/stations/KSNS" \
  -H "Accept: application/geo+json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

Get latest observation:
```bash
curl -s "https://api.weather.gov/stations/KSNS/observations/latest" \
  -H "Accept: application/geo+json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

**Response format:** GeoJSON with wind speed already in km/h (`unitCode: "wmoUnit:km_h-1"`), direction in degrees

**Note:** NWS API is US-only. International coordinates return 404.

### Pioupiou/OpenWindMap

Get all stations globally with latest measurements:
```bash
curl -s "http://api.pioupiou.fr/v1/live-with-meta/all" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

Get metadata for a specific station:
```bash
# Station ID: 1701 (Tuniberg, Germany)
curl -s "http://api.pioupiou.fr/v1/stations/1701" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

Get latest measurement for a specific station:
```bash
# Station ID: 1701
curl -s "http://api.pioupiou.fr/v1/live/1701" \
  -H "Accept: application/json" \
  -H "User-Agent: FreeFlightLog/1.0" | python3 -m json.tool
```

**Example Response (live-with-meta/all):**
```json
{
  "data": [
    {
      "id": 1701,
      "location": {
        "latitude": 47.967,
        "longitude": 7.766,
        "date": "2024-10-21T09:30:00.000Z"
      },
      "meta": {
        "name": "Tuniberg"
      },
      "status": {
        "state": "on",
        "date": "2025-01-15T10:23:45.000Z"
      },
      "measurements": {
        "wind_heading": 270,
        "wind_speed_avg": 1.75,
        "wind_speed_max": 3.75,
        "date": "2025-01-15T10:23:00.000Z"
      }
    }
  ]
}
```

**Response format:**
- Wind speeds already in km/h (`wind_speed_avg`, `wind_speed_max`)
- Direction in degrees (`wind_heading`)
- Measurements represent 4-minute average before `measurements.date`
- Check `status.state == "on"` to verify station is online

## Data Sources

### NWS (National Weather Service)
The US national weather service
- Limited to US only
- Two approaches for fetching stations:
  - Get the n nearest stations to a point by looking up the station nearest a grid (2.5km area). Then find the stations that are in the bounding box and look up each individually. Use aggressive caching.
  - Download all stations in a grid point's observation network (~50 stations per grid) 