import '../../data/models/weather_station_source.dart';
import 'weather_station_provider.dart';
import 'aviation_weather_center_provider.dart';
import 'nws_weather_provider.dart';
import 'pioupiou_weather_provider.dart';

/// Centralized registry mapping sources to provider implementations
///
/// Provides a single source of truth for accessing weather station providers
/// based on their source type. Simplifies provider lookup and ensures type safety.
class WeatherStationProviderRegistry {
  /// Map of sources to their provider implementations
  static final Map<WeatherStationSource, WeatherStationProvider> _providers = {
    WeatherStationSource.awcMetar: AviationWeatherCenterProvider.instance,
    WeatherStationSource.nws: NwsWeatherProvider.instance,
    WeatherStationSource.pioupiou: PioupiouWeatherProvider.instance,
  };

  /// Get provider for a specific source
  ///
  /// Throws [StateError] if no provider is registered for the source
  static WeatherStationProvider getProvider(WeatherStationSource source) {
    final provider = _providers[source];
    if (provider == null) {
      throw StateError('No provider registered for source: $source');
    }
    return provider;
  }

  /// Get all registered providers
  static List<WeatherStationProvider> getAllProviders() {
    return _providers.values.toList();
  }

  /// Get all registered sources
  static List<WeatherStationSource> getAllSources() {
    return _providers.keys.toList();
  }
}
