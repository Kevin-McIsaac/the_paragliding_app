import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../data/models/wind_forecast.dart';
import 'logging_service.dart';

/// One-hour on-disk cache of Open-Meteo forecasts.
///
/// The in-memory cache in [WeatherService] dies with the process, so every
/// launch spent the free API budget again. The budget is weighted per
/// location: one map view costs about 190 calls out of the 600 allowed per
/// minute. Keeping fresh forecasts on disk makes a relaunch free.
///
/// Entries are keyed exactly like the in-memory cache (`lat_lon_model`), and
/// an entry older than [ttl] is dropped on load and never written.
class WeatherForecastCache {
  WeatherForecastCache({
    Future<Directory> Function()? directoryProvider,
    this.ttl = const Duration(hours: 1),
    this.maxEntries = 500,
  }) : _directoryProvider = directoryProvider ?? getApplicationDocumentsDirectory;

  static const String fileName = 'weather_forecasts.json';
  static const int schemaVersion = 1;

  /// Forecasts at least this old are dropped on load and never written.
  final Duration ttl;

  /// Upper bound on stored entries, newest first, so the file cannot grow
  /// without limit while panning.
  final int maxEntries;

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async {
    final directory = await _directoryProvider();
    return File('${directory.path}/$fileName');
  }

  /// Read the fresh entries. A missing, unreadable or malformed file returns
  /// an empty map: the cache is an optimisation, never a source of failure.
  Future<Map<String, WindForecast>> load({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(ttl);
    try {
      final file = await _file();
      if (!await file.exists()) return {};

      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return {};
      if (decoded['version'] != schemaVersion) return {};

      final entries = decoded['entries'];
      if (entries is! Map<String, dynamic>) return {};

      final forecasts = <String, WindForecast>{};
      for (final entry in entries.entries) {
        try {
          final forecast = WindForecast.fromJson(entry.value as Map<String, dynamic>);
          if (forecast.fetchedAt.isBefore(cutoff)) continue;
          forecasts[entry.key] = forecast;
        } catch (error) {
          // One bad entry must not discard every other forecast.
          LoggingService.info('Dropping malformed weather cache entry ${entry.key}: $error');
        }
      }
      return forecasts;
    } catch (error) {
      LoggingService.error('Failed to read the weather forecast cache', error);
      return {};
    }
  }

  /// Write the fresh entries, newest first, capped at [maxEntries].
  Future<void> save(Map<String, WindForecast> forecasts, {DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(ttl);
    final fresh = forecasts.entries
        .where((entry) => !entry.value.fetchedAt.isBefore(cutoff))
        .toList()
      ..sort((a, b) => b.value.fetchedAt.compareTo(a.value.fetchedAt));

    try {
      final file = await _file();
      await file.parent.create(recursive: true);

      final payload = jsonEncode({
        'version': schemaVersion,
        'savedAt': DateTime.now().toIso8601String(),
        'entries': {
          for (final entry in fresh.take(maxEntries)) entry.key: entry.value.toJson(),
        },
      });

      // Write-then-rename: a process killed mid-write must not leave a
      // truncated cache that the next launch has to parse.
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(payload, flush: true);
      await temporary.rename(file.path);
    } catch (error) {
      LoggingService.error('Failed to write the weather forecast cache', error);
    }
  }

  /// Remove the file. Failure is logged and ignored, like [load] and [save].
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      LoggingService.error('Failed to delete the weather forecast cache', error);
    }
  }
}
