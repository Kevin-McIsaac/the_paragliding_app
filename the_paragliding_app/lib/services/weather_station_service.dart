import 'dart:async';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/weather_station.dart';
import '../data/models/weather_station_source.dart';
import '../data/models/wind_data.dart';
import 'logging_service.dart';
import 'weather_providers/weather_station_provider.dart';
import 'weather_providers/weather_station_provider_registry.dart';

/// Progress callback for individual provider completion
/// Provides cumulative deduplicated stations after each provider completes.
/// UI should REPLACE (not add to) its station list with the provided stations
/// to create a progressive appearance as the cumulative list grows.
typedef ProviderProgressCallback = void Function({
  required WeatherStationSource source,
  required String displayName,
  required bool success,
  required int stationCount,
  required List<WeatherStation> stations,  // Cumulative deduplicated list
});

/// Orchestrator service for weather station data from multiple providers
/// Manages METAR, NOAA CDO, and potentially other providers
/// Handles deduplication, caching, and parallel fetching
class WeatherStationService {
  static final WeatherStationService instance = WeatherStationService._();
  WeatherStationService._();


  /// Distance threshold for considering stations as duplicates (meters)
  /// Increased to 150m to handle coordinate precision differences between providers
  static const double _deduplicationDistanceMeters = 150.0;

  /// Get weather stations in a bounding box from all enabled providers
  /// Fetches in parallel, then deduplicates and returns combined results
  /// Optional [onProgress] callback reports each provider's completion
  Future<List<WeatherStation>> getStationsInBounds(
    LatLngBounds bounds, {
    ProviderProgressCallback? onProgress,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Get enabled providers
      final enabledProviders = await _getEnabledProviders();

      if (enabledProviders.isEmpty) {
        LoggingService.info('No weather station providers enabled');
        return [];
      }

      LoggingService.structured('WEATHER_STATION_FETCH_START', {
        'enabled_providers': enabledProviders.map((p) => p.source.name).toList(),
        'bounds': '${bounds.south},${bounds.west},${bounds.north},${bounds.east}',
      });

      // Accumulator for progressive results
      final List<WeatherStation> allStations = [];
      final List<List<WeatherStation>> providerResults = List.filled(enabledProviders.length, []);
      final Set<WeatherStationSource> providersWithApiCalls = {}; // Track which providers made API calls

      // Fetch from all enabled providers with progressive updates
      final futures = enabledProviders.asMap().entries.map((entry) async {
        final index = entry.key;
        final provider = entry.value;

        try {
          // Pass callback directly to provider - let provider decide when to call it
          final stations = await provider.fetchStations(
            bounds,
            onApiCallStart: onProgress != null
                ? () {
                    // Provider is notifying that it's making an API call
                    providersWithApiCalls.add(provider.source); // Track that this provider made an API call
                    final deduplicatedSoFar = _deduplicateStations(allStations);
                    onProgress.call(
                      source: provider.source,
                      displayName: provider.displayName,
                      success: true,
                      stationCount: 0, // API call starting, no results yet
                      stations: deduplicatedSoFar,
                    );
                  }
                : null,
          );
          LoggingService.info('${provider.displayName}: fetched ${stations.length} stations');

          // Store result
          providerResults[index] = stations;

          // Add to running total and deduplicate
          allStations.addAll(stations);
          final deduplicatedSoFar = _deduplicateStations(allStations);

          // Only report progress if:
          // 1. Provider returned stations (stationCount > 0), OR
          // 2. Provider made an API call (is in providersWithApiCalls set)
          // This ensures providers that skip API calls don't appear in overlay
          // But providers that made API calls get completion even with 0 results
          if (stations.isNotEmpty || providersWithApiCalls.contains(provider.source)) {
            // Report cumulative stations (deduplicated) - UI will replace all stations with this list
            onProgress?.call(
              source: provider.source,
              displayName: provider.displayName,
              success: true,
              stationCount: stations.length,
              stations: deduplicatedSoFar,  // Cumulative deduplicated list, not incremental
            );
          }

          return stations;
        } catch (e, stackTrace) {
          LoggingService.error('${provider.displayName}: fetch failed', e, stackTrace);

          // Only report error if provider made an API call
          // This prevents providers that error before API calls from showing in overlay
          if (providersWithApiCalls.contains(provider.source)) {
            // Report error with current stations (no new ones from this provider)
            final deduplicatedSoFar = _deduplicateStations(allStations);
            onProgress?.call(
              source: provider.source,
              displayName: provider.displayName,
              success: false,
              stationCount: 0,
              stations: deduplicatedSoFar,
            );
          }

          return <WeatherStation>[];
        }
      });

      final results = await Future.wait(futures);

      // Log summary of which providers returned data vs were skipped
      final providerSummary = <String, dynamic>{};
      for (var i = 0; i < enabledProviders.length; i++) {
        final provider = enabledProviders[i];
        final count = results[i].length;
        providerSummary[provider.source.name] = {
          'station_count': count,
          'status': count > 0 ? 'data_returned' : 'skipped_or_empty',
        };
      }

      LoggingService.structured('WEATHER_PROVIDERS_SUMMARY', {
        'total_providers': enabledProviders.length,
        'providers': providerSummary,
      });

      // Final combined results (for return value compatibility)
      allStations.clear();
      allStations.addAll(results.expand((list) => list));

      stopwatch.stop();

      LoggingService.structured('WEATHER_STATION_FETCH_COMPLETE', {
        'total_stations_before_dedup': allStations.length,
        'fetch_time_ms': stopwatch.elapsedMilliseconds,
        'by_provider': {
          for (var i = 0; i < enabledProviders.length; i++)
            enabledProviders[i].source.name: results[i].length,
        },
      });

      // Deduplicate stations
      final dedupStopwatch = Stopwatch()..start();
      final deduplicatedStations = _deduplicateStations(allStations);
      dedupStopwatch.stop();

      LoggingService.performance(
        'Station deduplication',
        Duration(milliseconds: dedupStopwatch.elapsedMilliseconds),
        '${allStations.length} → ${deduplicatedStations.length} stations',
      );

      return deduplicatedStations;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch weather stations', e, stackTrace);
      return [];
    }
  }

  /// Get weather data for a list of stations
  /// Routes each station to its appropriate provider
  Future<Map<String, WindData>> getWeatherForStations(
    List<WeatherStation> stations,
  ) async {
    if (stations.isEmpty) return {};

    try {
      // Group stations by provider
      final stationsByProvider = <WeatherStationSource, List<WeatherStation>>{};
      for (final station in stations) {
        stationsByProvider.putIfAbsent(station.source, () => []).add(station);
      }

      // Fetch weather data from each provider in parallel
      final futures = stationsByProvider.entries.map((entry) async {
        final provider = WeatherStationProviderRegistry.getProvider(entry.key);

        try {
          return await provider.fetchWeatherData(entry.value);
        } catch (e, stackTrace) {
          LoggingService.error('${provider.displayName}: weather data fetch failed', e, stackTrace);
          return <String, WindData>{};
        }
      });

      final results = await Future.wait(futures);

      // Combine all results
      final combinedData = <String, WindData>{};
      for (final result in results) {
        combinedData.addAll(result);
      }

      LoggingService.structured('WEATHER_DATA_FETCHED', {
        'total_stations': stations.length,
        'stations_with_data': combinedData.length,
      });

      return combinedData;
    } catch (e, stackTrace) {
      LoggingService.error('Failed to fetch weather data', e, stackTrace);
      return {};
    }
  }

  /// Deduplicate stations from multiple providers
  /// Keeps station with newest data when duplicates found within threshold distance
  List<WeatherStation> _deduplicateStations(List<WeatherStation> stations) {
    if (stations.length <= 1) return stations;

    final result = <WeatherStation>[];
    final discarded = <WeatherStation>[];

    for (final station in stations) {
      // Check if this station is a duplicate of any in result
      WeatherStation? duplicate;
      double? duplicateDistance;

      for (final existing in result) {
        final distance = _calculateDistance(
          station.latitude,
          station.longitude,
          existing.latitude,
          existing.longitude,
        );

        if (distance <= _deduplicationDistanceMeters) {
          duplicate = existing;
          duplicateDistance = distance;
          break;
        }
      }

      if (duplicate != null) {
        // Found a duplicate - decide which to keep
        final shouldReplace = _shouldReplaceStation(duplicate, station);

        if (shouldReplace) {
          // Replace existing with new station
          result.remove(duplicate);
          result.add(station);
          discarded.add(duplicate);
        } else {
          // Keep existing, discard new
          discarded.add(station);
        }
      } else {
        // No duplicate found, add to result
        result.add(station);
      }
    }

    // Log summary
    if (discarded.isNotEmpty) {
      final keptByProvider = <String, int>{};
      for (final station in result) {
        final providerId = station.source.name;
        keptByProvider[providerId] = (keptByProvider[providerId] ?? 0) + 1;
      }

      LoggingService.structured('WEATHER_STATION_DEDUPLICATION_SUMMARY', {
        'original_count': stations.length,
        'final_count': result.length,
        'duplicates_removed': discarded.length,
        'by_provider': keptByProvider,
      });
    }

    return result;
  }

  /// Determine if we should replace an existing station with a new one
  /// Prioritizes: 1) Has wind data, 2) Newer timestamp
  bool _shouldReplaceStation(WeatherStation existing, WeatherStation newStation) {
    // If one has data and the other doesn't, prefer the one with data
    if (existing.windData == null && newStation.windData != null) {
      return true;
    }
    if (existing.windData != null && newStation.windData == null) {
      return false;
    }

    // If both have data (or both don't), prefer newer timestamp
    if (existing.windData != null && newStation.windData != null) {
      return newStation.windData!.timestamp.isAfter(existing.windData!.timestamp);
    }

    // Neither has data - keep existing (arbitrary choice)
    return false;
  }

  /// Calculate distance between two lat/lon points in meters
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const distance = Distance();
    return distance.distance(LatLng(lat1, lon1), LatLng(lat2, lon2));
  }

  /// Get list of enabled providers based on preferences
  Future<List<WeatherStationProvider>> _getEnabledProviders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = <WeatherStationProvider>[];

      for (final source in WeatherStationProviderRegistry.getAllSources()) {
        final key = 'weather_provider_${source.name}_enabled';
        final isEnabled = prefs.getBool(key) ?? true; // Default enabled

        if (isEnabled) {
          final provider = WeatherStationProviderRegistry.getProvider(source);
          if (await provider.isConfigured()) {
            enabled.add(provider);
          }
        }
      }

      return enabled;
    } catch (e) {
      LoggingService.error('Failed to get enabled providers', e);
      return [];
    }
  }

  /// Set provider enabled state
  static Future<void> setProviderEnabled(WeatherStationSource source, bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('weather_provider_${source.name}_enabled', enabled);
      LoggingService.action('WeatherProvider', source.name, {'enabled': enabled});
    } catch (e) {
      LoggingService.error('Failed to set provider enabled state', e);
    }
  }

  /// Get provider enabled state
  static Future<bool> isProviderEnabled(WeatherStationSource source) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('weather_provider_${source.name}_enabled') ?? true;
    } catch (e) {
      LoggingService.error('Failed to get provider enabled state', e);
      return true; // Fallback - enable by default
    }
  }

  /// Clear all caches for all providers
  void clearCache() {
    for (final provider in WeatherStationProviderRegistry.getAllProviders()) {
      provider.clearCache();
    }
    LoggingService.info('All weather station caches cleared');
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    final stats = <String, dynamic>{};
    for (final provider in WeatherStationProviderRegistry.getAllProviders()) {
      stats[provider.source.name] = provider.getCacheStats();
    }
    return stats;
  }
}
