import 'dart:async';
import 'package:flutter/foundation.dart';
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
  bool passComplete,  // True on the final push of a provider's background pass
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
  ///
  /// [providersForTest] bypasses the enabled-provider lookup so a test can
  /// drive this method with fake providers instead of the live registry.
  Future<List<WeatherStation>> getStationsInBounds(
    LatLngBounds bounds, {
    ProviderProgressCallback? onProgress,
    @visibleForTesting List<WeatherStationProvider>? providersForTest,
  }) async {
    try {
      final stopwatch = Stopwatch()..start();

      // Get enabled providers
      final enabledProviders = providersForTest ?? await _getEnabledProviders();

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
      final Set<WeatherStationSource> providersWithApiCalls = {}; // Track which providers made API calls

      // Live station state pushed by push-based providers (WU PWS), keyed by
      // source then station key. Such a provider's fetchStations return is its
      // *cache* answer, not its result, so this - not the return - is the truth
      // for those sources. See the final assembly below.
      final pushedBySource =
          <WeatherStationSource, Map<String, WeatherStation>>{};
      // Sources that have delivered a terminal push (the provider's full
      // in-bounds list) during this call. Only those may be trusted over the
      // return: a pass superseded mid-flight can push a delta batch and then
      // never send its terminal list, and using that partial accumulator would
      // drop every station the delta did not mention.
      final terminalPushedSources = <WeatherStationSource>{};

      // Fetch from all enabled providers with progressive updates
      final futures = enabledProviders.asMap().entries.map((entry) async {
        final provider = entry.value;

        try {
          // Whether the provider used the push channel - push-based providers
          // signal their own terminal event; blocking providers report
          // exactly twice (start + final), so their await-return IS terminal.
          bool hasPushed = false;
          // Pass callback directly to provider - let provider decide when to call it
          final stations = await provider.fetchStations(
            bounds,
            onApiCallStart: onProgress != null
                ? () {
                    // Provider is notifying that it's making an API call
                    providersWithApiCalls.add(provider.source); // Track that this provider made an API call
                    onProgress.call(
                      source: provider.source,
                      displayName: provider.displayName,
                      success: true,
                      stationCount: 0, // API call starting, no results yet
                      // Nothing has changed for the consumer to merge - this
                      // is a start signal, not a station list.
                      stations: const <WeatherStation>[],
                    );
                  }
                : null,
            // Cache-first providers (WU PWS) push refinements as their
            // background passes land; each update flows through the same
            // progress channel as a completion so the map re-renders.
            // Intermediate pushes carry only the stations whose state changed;
            // the final push carries passComplete and the full list.
            //
            // Wired unconditionally rather than only when a UI listener exists:
            // the accumulated state is what makes this method's *return* honest
            // for a push-based provider, which a caller without onProgress
            // still relies on.
            onStationsUpdated: (updatedStations, {passComplete = false}) {
              hasPushed = true;
              // Deltas merge; the terminal push carries the provider's full
              // in-bounds list, so it replaces.
              final accumulated = pushedBySource.putIfAbsent(
                provider.source,
                () => <String, WeatherStation>{},
              );
              if (passComplete) {
                accumulated.clear();
                terminalPushedSources.add(provider.source);
              }
              for (final station in updatedStations) {
                accumulated[station.key] = station;
              }
              // Forward the push as-is: it is this provider's own list, never
              // the cumulative one from every provider.
              onProgress?.call(
                source: provider.source,
                displayName: provider.displayName,
                success: true,
                stationCount: updatedStations.length,
                stations: updatedStations,
                passComplete: passComplete,
              );
            },
          );
          LoggingService.info('${provider.displayName}: fetched ${stations.length} stations');

          // Only report progress if:
          // 1. Provider returned stations (stationCount > 0), OR
          // 2. Provider made an API call (is in providersWithApiCalls set)
          // This ensures providers that skip API calls don't appear in overlay
          // But providers that made API calls get completion even with 0 results
          //
          // A push-based provider's return is its cache answer, not its result:
          // its own final push carries the terminal event, so this one must not
          // claim completion or the overlay closes before the live pass lands.
          if (!hasPushed &&
              (stations.isNotEmpty ||
                  providersWithApiCalls.contains(provider.source))) {
            onProgress?.call(
              source: provider.source,
              displayName: provider.displayName,
              success: true,
              stationCount: stations.length,
              // This provider's own stations - the consumer merges per source.
              stations: stations,
              // Blocking providers report exactly twice (start + final);
              // this is their terminal event.
              passComplete: !provider.pushesProgressively,
            );
          }

          return stations;
        } catch (e, stackTrace) {
          LoggingService.error('${provider.displayName}: fetch failed', e, stackTrace);

          // Only report error if provider made an API call
          // This prevents providers that error before API calls from showing in overlay
          if (providersWithApiCalls.contains(provider.source)) {
            // Failure carries no stations: the consumer keeps what it has and
            // just records the error state for this source.
            onProgress?.call(
              source: provider.source,
              displayName: provider.displayName,
              success: false,
              stationCount: 0,
              stations: const <WeatherStation>[],
              passComplete: true,
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

      // Final combined results.
      //
      // Per provider, prefer the accumulated pushes over the fetchStations
      // return for a push-based provider once it has sent its terminal list.
      // Its return is the cache answer it started from, so rebuilding purely
      // from `results` threw away every reading the background pass had just
      // delivered: the caller's terminal assignment then cleared them and the
      // markers hung on "wind loading..." (seen live 2026-09-12 near Jenbach -
      // 9 WU stations read with wind, the final result carrying 0 of them). A
      // provider that has not sent a terminal push still falls back to its
      // return, and any push arriving after this returns keeps flowing through
      // onStationsUpdated.
      final combined = <WeatherStation>[];
      final countBySource = <String, int>{};
      for (var i = 0; i < enabledProviders.length; i++) {
        final provider = enabledProviders[i];
        final pushed = pushedBySource[provider.source];
        final usePushed = provider.pushesProgressively &&
            pushed != null &&
            terminalPushedSources.contains(provider.source);
        final chosen = usePushed ? pushed.values.toList() : results[i];
        combined.addAll(chosen);
        countBySource[provider.source.name] = chosen.length;
      }
      allStations.clear();
      allStations.addAll(combined);

      stopwatch.stop();

      LoggingService.structured('WEATHER_STATION_FETCH_COMPLETE', {
        'total_stations_before_dedup': allStations.length,
        'fetch_time_ms': stopwatch.elapsedMilliseconds,
        'by_provider': countBySource,
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

      for (final existing in result) {
        final distance = _calculateDistance(
          station.latitude,
          station.longitude,
          existing.latitude,
          existing.longitude,
        );

        if (distance <= _deduplicationDistanceMeters) {
          duplicate = existing;
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
