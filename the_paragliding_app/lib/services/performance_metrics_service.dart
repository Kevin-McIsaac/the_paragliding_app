import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'logging_service.dart';

/// Advanced performance metrics tracking service
/// Provides percentile tracking, cache metrics, and performance analytics
class PerformanceMetricsService {
  static final PerformanceMetricsService _instance = PerformanceMetricsService._internal();
  factory PerformanceMetricsService() => _instance;
  PerformanceMetricsService._internal();

  // Operation metrics storage
  static final Map<String, List<int>> _operationDurations = {};
  static final Map<String, _QueryMetrics> _queryMetrics = {};
  static final Map<String, _CacheMetrics> _cacheMetrics = {};

  // Configuration
  static const int _maxSamples = 1000;
  static const Duration _summaryInterval = Duration(minutes: 5);
  static const int _slowQueryThresholdMs = 500;

  // Sampling configuration
  static final Map<String, int> _samplingRates = {
    'database_query': 1, // Log all database queries
    'cache_lookup': 10, // Log 1 in 10 cache lookups
    'ui_interaction': 5, // Log 1 in 5 UI interactions
  };

  // Summary timer
  static Timer? _summaryTimer;
  static bool _initialized = false;

  /// Initialize the metrics service
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Start periodic summary logging
    _summaryTimer = Timer.periodic(_summaryInterval, (_) {
      logPerformanceSummary();
    });

    LoggingService.info('[METRICS] Performance metrics service initialized');
  }

  /// Dispose of resources
  static void dispose() {
    _summaryTimer?.cancel();
    _summaryTimer = null;
    _initialized = false;
  }

  /// Track operation duration with automatic percentile calculation
  static void trackOperation(String operation, int durationMs, {
    Map<String, dynamic>? metadata,
    String? sql,
    int? resultCount,
  }) {
    if (!kDebugMode) return;

    // Check sampling rate
    if (!_shouldSample(operation)) return;

    // Store duration for percentile calculation
    _operationDurations.putIfAbsent(operation, () => []);
    final durations = _operationDurations[operation]!;
    durations.add(durationMs);

    // Limit stored samples
    if (durations.length > _maxSamples) {
      durations.removeAt(0);
    }

    // Track query-specific metrics
    if (sql != null) {
      _trackQueryMetrics(operation, durationMs, sql, resultCount ?? 0);
    }

    // Log slow queries with full SQL
    if (durationMs > _slowQueryThresholdMs && sql != null) {
      LoggingService.warning('[SLOW_QUERY] $operation', {
        'duration_ms': durationMs,
        'sql': sql,
        'result_count': resultCount,
        ...?metadata,
      });
    }

    // Log with percentiles if enough samples
    if (durations.length >= 10) {
      final percentiles = _calculatePercentiles(durations);
      LoggingService.structured('PERF_METRICS', {
        'operation': operation,
        'duration_ms': durationMs,
        'p50': percentiles['p50'],
        'p95': percentiles['p95'],
        'p99': percentiles['p99'],
        'samples': durations.length,
        ...?metadata,
      });
    }
  }

  /// Track cache operations
  static void trackCacheOperation(String cacheName, bool hit, {
    int? sizeBytes,
    String? key,
  }) {
    if (!kDebugMode) return;

    // Check sampling for cache operations
    if (!_shouldSample('cache_lookup')) return;

    _cacheMetrics.putIfAbsent(cacheName, () => _CacheMetrics());
    final metrics = _cacheMetrics[cacheName]!;

    if (hit) {
      metrics.hits++;
    } else {
      metrics.misses++;
    }

    if (sizeBytes != null) {
      metrics.totalBytes += sizeBytes;
    }

    // Log cache metrics periodically (every 100 operations)
    if ((metrics.hits + metrics.misses) % 100 == 0) {
      final hitRate = metrics.hits / (metrics.hits + metrics.misses) * 100;
      LoggingService.structured('CACHE_METRICS', {
        'cache': cacheName,
        'hit_rate': '${hitRate.toStringAsFixed(1)}%',
        'hits': metrics.hits,
        'misses': metrics.misses,
        'total_bytes': metrics.totalBytes,
      });
    }
  }

  /// Track user interaction response time
  static void trackUserInteraction(String action, int responseTimeMs) {
    if (!kDebugMode) return;

    // Check sampling for UI interactions
    if (!_shouldSample('ui_interaction')) return;

    trackOperation('ui_$action', responseTimeMs, metadata: {
      'interaction_type': 'user',
      'action': action,
    });
  }

  /// Track memory usage during operations
  static void trackMemoryUsage(String context, int memoryMb) {
    if (!kDebugMode) return;

    LoggingService.structured('MEMORY_USAGE', {
      'context': context,
      'memory_mb': memoryMb,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  /// Calculate percentiles for a list of values
  static Map<String, int> _calculatePercentiles(List<int> values) {
    if (values.isEmpty) {
      return {'p50': 0, 'p95': 0, 'p99': 0};
    }

    final sorted = List<int>.from(values)..sort();

    int percentile(double p) {
      final index = (sorted.length * p).round().clamp(0, sorted.length - 1);
      return sorted[index];
    }

    return {
      'p50': percentile(0.50),
      'p95': percentile(0.95),
      'p99': percentile(0.99),
    };
  }

  /// Track query-specific metrics (result size vs time correlation)
  static void _trackQueryMetrics(String operation, int durationMs, String sql, int resultCount) {
    _queryMetrics.putIfAbsent(operation, () => _QueryMetrics());
    final metrics = _queryMetrics[operation]!;

    metrics.addSample(durationMs, resultCount);

    // Analyze correlation periodically
    if (metrics.samples.length >= 20) {
      final correlation = metrics.calculateCorrelation();
      if (correlation.abs() > 0.7) {
        LoggingService.structured('QUERY_CORRELATION', {
          'operation': operation,
          'correlation': correlation.toStringAsFixed(3),
          'interpretation': correlation > 0
            ? 'Query time increases with result size'
            : 'Query time decreases with result size',
          'samples': metrics.samples.length,
        });
      }
    }
  }

  /// Check if operation should be sampled
  static bool _shouldSample(String operation) {
    final rate = _samplingRates[operation] ?? 1;
    if (rate == 1) return true;
    return math.Random().nextInt(rate) == 0;
  }

  /// Log comprehensive performance summary
  static void logPerformanceSummary() {
    if (!kDebugMode || _operationDurations.isEmpty) return;

    LoggingService.info('[PERF_SUMMARY] === Performance Summary ===');

    // Log percentiles for each operation
    _operationDurations.forEach((operation, durations) {
      if (durations.isEmpty) return;

      final percentiles = _calculatePercentiles(durations);
      final avg = durations.reduce((a, b) => a + b) ~/ durations.length;

      LoggingService.structured('OPERATION_SUMMARY', {
        'operation': operation,
        'samples': durations.length,
        'avg_ms': avg,
        'p50_ms': percentiles['p50'],
        'p95_ms': percentiles['p95'],
        'p99_ms': percentiles['p99'],
        'min_ms': durations.reduce(math.min),
        'max_ms': durations.reduce(math.max),
      });
    });

    // Log cache performance
    _cacheMetrics.forEach((cacheName, metrics) {
      final hitRate = metrics.hits > 0
        ? (metrics.hits / (metrics.hits + metrics.misses) * 100)
        : 0.0;

      LoggingService.structured('CACHE_SUMMARY', {
        'cache': cacheName,
        'hit_rate': '${hitRate.toStringAsFixed(1)}%',
        'total_operations': metrics.hits + metrics.misses,
        'total_mb': (metrics.totalBytes / 1024 / 1024).toStringAsFixed(2),
      });
    });

    // Log query correlations
    _queryMetrics.forEach((operation, metrics) {
      if (metrics.samples.length < 10) return;

      final correlation = metrics.calculateCorrelation();
      LoggingService.structured('QUERY_ANALYSIS', {
        'operation': operation,
        'samples': metrics.samples.length,
        'avg_duration_ms': metrics.averageDuration.toStringAsFixed(1),
        'avg_result_count': metrics.averageResultCount.toStringAsFixed(0),
        'size_time_correlation': correlation.toStringAsFixed(3),
      });
    });
  }

  /// Get current performance statistics
  static Map<String, dynamic> getStatistics() {
    final stats = <String, dynamic>{};

    // Add operation percentiles
    _operationDurations.forEach((operation, durations) {
      if (durations.isEmpty) return;

      final percentiles = _calculatePercentiles(durations);
      stats['$operation.p50'] = percentiles['p50'];
      stats['$operation.p95'] = percentiles['p95'];
      stats['$operation.p99'] = percentiles['p99'];
    });

    // Add cache hit rates
    _cacheMetrics.forEach((cacheName, metrics) {
      final hitRate = metrics.hits > 0
        ? (metrics.hits / (metrics.hits + metrics.misses) * 100)
        : 0.0;
      stats['cache.$cacheName.hit_rate'] = hitRate;
    });

    return stats;
  }

  /// Reset all metrics (useful for testing)
  static void reset() {
    _operationDurations.clear();
    _queryMetrics.clear();
    _cacheMetrics.clear();
  }
}

/// Cache metrics tracking
class _CacheMetrics {
  int hits = 0;
  int misses = 0;
  int totalBytes = 0;
}

/// Query metrics for correlation analysis
class _QueryMetrics {
  final List<_QuerySample> samples = [];
  static const int _maxSamples = 100;

  void addSample(int durationMs, int resultCount) {
    samples.add(_QuerySample(durationMs, resultCount));
    if (samples.length > _maxSamples) {
      samples.removeAt(0);
    }
  }

  double get averageDuration {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.durationMs).reduce((a, b) => a + b) / samples.length;
  }

  double get averageResultCount {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.resultCount).reduce((a, b) => a + b) / samples.length;
  }

  /// Calculate Pearson correlation coefficient between result size and duration
  double calculateCorrelation() {
    if (samples.length < 2) return 0;

    final avgDuration = averageDuration;
    final avgCount = averageResultCount;

    double numerator = 0;
    double denominatorDuration = 0;
    double denominatorCount = 0;

    for (final sample in samples) {
      final durationDiff = sample.durationMs - avgDuration;
      final countDiff = sample.resultCount - avgCount;

      numerator += durationDiff * countDiff;
      denominatorDuration += durationDiff * durationDiff;
      denominatorCount += countDiff * countDiff;
    }

    if (denominatorDuration == 0 || denominatorCount == 0) return 0;

    return numerator / (math.sqrt(denominatorDuration) * math.sqrt(denominatorCount));
  }
}

class _QuerySample {
  final int durationMs;
  final int resultCount;

  _QuerySample(this.durationMs, this.resultCount);
}