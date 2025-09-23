import 'dart:async';
import '../services/logging_service.dart';
import '../services/airspace_metadata_cache.dart';
import '../services/airspace_disk_cache.dart';

/// Monitors and logs airspace cache performance metrics
class AirspacePerformanceLogger {
  static AirspacePerformanceLogger? _instance;
  final AirspaceMetadataCache _metadataCache = AirspaceMetadataCache.instance;
  final AirspaceDiskCache _diskCache = AirspaceDiskCache.instance;

  // Performance tracking
  final Map<String, List<Duration>> _operationTimings = {};
  final Map<String, int> _operationCounts = {};
  DateTime _startTime = DateTime.now();
  Timer? _periodicLogger;

  // Thresholds for alerts
  static const Duration _slowOperationThreshold = Duration(milliseconds: 500);
  static const double _lowHitRateThreshold = 0.5;
  static const double _highMemoryUsageThreshold = 10.0; // MB

  AirspacePerformanceLogger._internal();

  static AirspacePerformanceLogger get instance {
    _instance ??= AirspacePerformanceLogger._internal();
    return _instance!;
  }

  /// Start periodic performance logging
  void startPeriodicLogging({Duration interval = const Duration(minutes: 5)}) {
    stopPeriodicLogging();
    _startTime = DateTime.now();

    _periodicLogger = Timer.periodic(interval, (_) async {
      await logPerformanceSummary();
    });

    LoggingService.info('Started airspace performance monitoring, interval: ${interval.inMinutes} minutes');
  }

  /// Stop periodic performance logging
  void stopPeriodicLogging() {
    _periodicLogger?.cancel();
    _periodicLogger = null;
  }

  /// Log an operation timing
  void logOperation(String operation, Duration duration, {Map<String, dynamic>? details}) {
    // Track timing
    _operationTimings.putIfAbsent(operation, () => []).add(duration);
    _operationCounts[operation] = (_operationCounts[operation] ?? 0) + 1;

    // Log if slow
    if (duration > _slowOperationThreshold) {
      LoggingService.structured('AIRSPACE_SLOW_OPERATION', {
        'operation': operation,
        'duration_ms': duration.inMilliseconds,
        'threshold_ms': _slowOperationThreshold.inMilliseconds,
        ...?details,
      });
    }
  }

  /// Log cache hit/miss
  void logCacheAccess({
    required String cacheType,
    required bool isHit,
    String? key,
    int? size,
  }) {
    final operation = '${cacheType}_${isHit ? 'hit' : 'miss'}';
    _operationCounts[operation] = (_operationCounts[operation] ?? 0) + 1;

    if (!isHit) {
      LoggingService.debug('Cache miss: type=$cacheType, key=$key');
    }
  }

  /// Log API request
  void logApiRequest({
    required String endpoint,
    required Duration duration,
    required int resultCount,
    required String bounds,
  }) {
    logOperation('api_request', duration, details: {
      'endpoint': endpoint,
      'result_count': resultCount,
      'bounds': bounds,
    });

    LoggingService.structured('AIRSPACE_API_REQUEST', {
      'endpoint': endpoint,
      'duration_ms': duration.inMilliseconds,
      'result_count': resultCount,
      'bounds': bounds,
    });
  }

  /// Log compression statistics
  void logCompression({
    required int originalSize,
    required int compressedSize,
    required Duration duration,
  }) {
    final ratio = 1.0 - (compressedSize / originalSize);

    LoggingService.structured('AIRSPACE_COMPRESSION', {
      'original_bytes': originalSize,
      'compressed_bytes': compressedSize,
      'ratio': ratio.toStringAsFixed(2),
      'duration_ms': duration.inMilliseconds,
    });
  }

  /// Log performance summary
  Future<void> logPerformanceSummary() async {
    try {
      final stats = await _diskCache.getStatistics();
      final metadataMetrics = _metadataCache.getPerformanceMetrics();
      final uptime = DateTime.now().difference(_startTime);

      // Calculate operation statistics
      final operationStats = <String, Map<String, dynamic>>{};
      for (final entry in _operationTimings.entries) {
        final timings = entry.value;
        if (timings.isNotEmpty) {
          final totalMs = timings.fold(0, (sum, d) => sum + d.inMilliseconds);
          final avgMs = totalMs ~/ timings.length;
          final maxMs = timings.map((d) => d.inMilliseconds).reduce((a, b) => a > b ? a : b);
          final minMs = timings.map((d) => d.inMilliseconds).reduce((a, b) => a < b ? a : b);

          operationStats[entry.key] = {
            'count': timings.length,
            'avg_ms': avgMs,
            'max_ms': maxMs,
            'min_ms': minMs,
            'total_ms': totalMs,
          };
        }
      }

      // Check for alerts
      final alerts = <String>[];

      // Check hit rate
      final tileHitRate = double.parse(
        metadataMetrics['tileCache']['hitRate'].toString().replaceAll('%', ''),
      ) / 100;
      if (tileHitRate < _lowHitRateThreshold) {
        alerts.add('Low tile cache hit rate: ${(tileHitRate * 100).toStringAsFixed(1)}%');
      }

      final geoHitRate = double.parse(
        metadataMetrics['geometryCache']['hitRate'].toString().replaceAll('%', ''),
      ) / 100;
      if (geoHitRate < _lowHitRateThreshold) {
        alerts.add('Low geometry cache hit rate: ${(geoHitRate * 100).toStringAsFixed(1)}%');
      }

      // Check memory usage
      final memoryMB = stats.totalMemoryBytes / (1024 * 1024);
      if (memoryMB > _highMemoryUsageThreshold) {
        alerts.add('High memory usage: ${memoryMB.toStringAsFixed(1)}MB');
      }

      // Log comprehensive summary
      LoggingService.structured('AIRSPACE_PERFORMANCE_SUMMARY', {
        'uptime_minutes': uptime.inMinutes,
        'cache_stats': {
          'total_geometries': stats.totalGeometries,
          'total_tiles': stats.totalTiles,
          'empty_tiles': stats.emptyTiles,
          'empty_tile_percent': stats.emptyTilePercent.toStringAsFixed(1),
          'duplicated_airspaces': stats.duplicatedAirspaces,
          'memory_mb': memoryMB.toStringAsFixed(2),
          'compressed_mb': (stats.compressedBytes / (1024 * 1024)).toStringAsFixed(2),
          'compression_ratio': stats.averageCompressionRatio.toStringAsFixed(2),
          'memory_reduction_percent': stats.memoryReductionPercent.toStringAsFixed(1),
        },
        'hit_rates': {
          'tile_cache': metadataMetrics['tileCache']['hitRate'],
          'geometry_cache': metadataMetrics['geometryCache']['hitRate'],
        },
        'operations': operationStats,
        'operation_counts': _operationCounts,
        'alerts': alerts,
      });

      // Log alerts separately if any
      for (final alert in alerts) {
        LoggingService.warning('Performance alert: $alert');
      }

      // Log memory savings
      if (stats.duplicatedAirspaces > 0) {
        final savedMB = (stats.duplicatedAirspaces * 50 * 1024) / (1024 * 1024); // Assume 50KB per duplicate
        LoggingService.info(
          'Deduplication saved ~${savedMB.toStringAsFixed(1)}MB by avoiding ${stats.duplicatedAirspaces} duplicates',
        );
      }

      // Reset short-term counters
      _resetShortTermMetrics();
    } catch (e, stack) {
      LoggingService.error('Failed to log performance summary', e, stack);
    }
  }

  /// Log cache efficiency
  Future<void> logCacheEfficiency() async {
    final stats = await _diskCache.getStatistics();
    // metadataMetrics extracted but not used

    final efficiency = {
      'deduplication': {
        'unique_geometries': stats.totalGeometries,
        'total_references': stats.totalGeometries + stats.duplicatedAirspaces,
        'space_saved_percent': stats.duplicatedAirspaces > 0
            ? ((stats.duplicatedAirspaces / (stats.totalGeometries + stats.duplicatedAirspaces)) * 100)
                .toStringAsFixed(1)
            : '0.0',
      },
      'compression': {
        'original_mb': (stats.totalMemoryBytes / (1024 * 1024)).toStringAsFixed(2),
        'compressed_mb': (stats.compressedBytes / (1024 * 1024)).toStringAsFixed(2),
        'ratio': stats.averageCompressionRatio.toStringAsFixed(2),
      },
      'empty_tiles': {
        'count': stats.emptyTiles,
        'percent': stats.emptyTilePercent.toStringAsFixed(1),
        'space_saved_kb': (stats.emptyTiles * 0.1).toStringAsFixed(1), // 100 bytes per empty tile
      },
    };

    LoggingService.structured('AIRSPACE_CACHE_EFFICIENCY', efficiency);
  }

  /// Log viewport processing
  void logViewportProcessing({
    required int tilesRequested,
    required int tilesCached,
    required int tilesEmpty,
    required int uniqueAirspaces,
    required Duration totalDuration,
  }) {
    LoggingService.structured('AIRSPACE_VIEWPORT_PROCESSING', {
      'tiles_requested': tilesRequested,
      'tiles_cached': tilesCached,
      'tiles_empty': tilesEmpty,
      'tiles_fetched': tilesRequested - tilesCached,
      'unique_airspaces': uniqueAirspaces,
      'duration_ms': totalDuration.inMilliseconds,
      'cache_hit_rate': tilesRequested > 0
          ? ((tilesCached / tilesRequested) * 100).toStringAsFixed(1)
          : '0.0',
    });
  }

  /// Reset short-term metrics
  void _resetShortTermMetrics() {
    // Keep only the last 100 timings per operation
    for (final entry in _operationTimings.entries) {
      final timings = entry.value;
      if (timings.length > 100) {
        _operationTimings[entry.key] = timings.sublist(timings.length - 100);
      }
    }
  }

  /// Clear all metrics
  void clearMetrics() {
    _operationTimings.clear();
    _operationCounts.clear();
    _startTime = DateTime.now();
    LoggingService.info('Cleared airspace performance metrics');
  }

  /// Get current metrics summary
  Map<String, dynamic> getCurrentMetrics() {
    final summary = <String, dynamic>{
      'uptime_seconds': DateTime.now().difference(_startTime).inSeconds,
      'operation_counts': Map<String, int>.from(_operationCounts),
      'operation_timings': <String, Map<String, int>>{},
    };

    // Add timing statistics
    for (final entry in _operationTimings.entries) {
      final timings = entry.value;
      if (timings.isNotEmpty) {
        final totalMs = timings.fold(0, (sum, d) => sum + d.inMilliseconds);
        summary['operation_timings'][entry.key] = {
          'count': timings.length,
          'avg_ms': totalMs ~/ timings.length,
        };
      }
    }

    return summary;
  }

  /// Dispose resources
  void dispose() {
    stopPeriodicLogging();
  }
}