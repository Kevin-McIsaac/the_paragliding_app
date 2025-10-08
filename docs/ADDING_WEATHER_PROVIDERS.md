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

## UI Integration

The provider automatically appears in the Map Filter dialog once registered:

**File:** `lib/presentation/widgets/map_filter_dialog.dart`

The dialog dynamically generates checkboxes from `WeatherStationProviderRegistry.getAllSources()`:

```dart
// METAR provider
_buildProviderCheckbox(
  value: _metarEnabled,
  label: 'METAR (Aviation)',
  subtitle: WeatherStationProviderRegistry.getProvider(WeatherStationSource.metar).description,
  onChanged: (value) => setState(() {
    _metarEnabled = value ?? true;
    _applyFiltersImmediately();
  }),
),

// Your provider will appear here automatically
```

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

```dart
// Station list: Long TTL (1 hour+)
Duration get cacheTTL => MapConstants.stationListCacheTTL;

// Weather data: Short TTL (5-15 minutes)
Duration get cacheTTL => MapConstants.weatherStationCacheTTL;
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


## Data Sources

### NWS
The US national weather service
- Limited to US only
- Two approaches. 
  - Get the n nearest stations to a point by looing up the station nearest a grid (2.5km area). Then find the stations that are in teh BB and look up each individually. Use agressive caching
  - DOwnload 