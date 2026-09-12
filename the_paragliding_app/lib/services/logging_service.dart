import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'claude_log_printer.dart';
import 'performance_metrics_service.dart';

/// Centralized logging service for The Paragliding App application
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();
  
  // Operation tracking
  static String? _currentOperationId;
  static final Map<String, int> _operationCounters = {};
  static const int _maxCounterEntries = 100;  // Prevent unbounded growth

  // Duplicate operation detection
  static final Set<String> _recentOperations = <String>{};

  // Claude-optimized logger with enhanced readability and navigation
  static final Logger _logger = Logger(
    // Profile builds are used for performance measurement, so they need the
    // same [P]/[D] output as debug - only release stays quiet
    level: kReleaseMode ? Level.warning : Level.debug,
    // Without this the package default, DevelopmentFilter, applies - and it
    // decides inside an assert():
    //
    //   var shouldLog = false;
    //   assert(() { if (event.level >= level!) shouldLog = true; return true; }());
    //   return shouldLog;
    //
    // Asserts are stripped in release, so it returns false for *every* event and
    // the `level` above is never consulted. A release build emitted nothing at
    // any severity - verified on 1.0.4+14, where logcat carried engine lines but
    // not one line of ours. ProductionFilter is a plain `event.level >= level`,
    // so the level gate does the filtering it looks like it does.
    filter: ProductionFilter(),
    printer: ClaudeLogPrinter(), // Always use Claude-optimized format
  );

  /// Log debug information with smart filtering for routine operations
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    // Skip routine debug messages that add noise without value
    if (_isRoutineDebugMessage(message)) return;
    _logger.d(message, error: error, stackTrace: stackTrace);
  }
  
  /// Check if debug message is routine and should be filtered
  static bool _isRoutineDebugMessage(String message) {
    // Filter out routine database queries and site lookups
    if (message.contains('Found ') && message.contains(' sites in bounds')) return true;
    if (message.contains('Retrieved ') && message.contains(' flights')) return true;
    if (message.contains('Getting overall statistics')) return true;
    
    return false;
  }
  
  /// Check if this operation has been logged recently to avoid duplicates
  static bool _isRecentDuplicateOperation(String operation) {
    if (_recentOperations.contains(operation)) {
      return true;
    }
    
    // Add to recent operations and clean up old ones
    _recentOperations.add(operation);
    
    // Keep set size manageable (last 10 operations)
    if (_recentOperations.length > 10) {
      _recentOperations.clear();
      _recentOperations.add(operation);
    }
    
    return false;
  }

  /// Log general information with duplicate detection for IGC parsing
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    // Suppress duplicate IGC parsing operations using structured keys
    if (message.contains('Successfully parsed date:')) {
      // Extract the date from the message for a unique key
      final dateMatch = RegExp(r'\d{4}-\d{2}-\d{2}').firstMatch(message);
      final operationKey = 'igc_parse_date_${dateMatch?.group(0) ?? 'unknown'}';
      if (_isRecentDuplicateOperation(operationKey)) {
        _logger.d('[IGC_DUPLICATE_SUPPRESSED] $message | at=logging_service.dart:${StackTrace.current.toString().split('\n')[1].split(':')[2]}');
        return;
      }
    } else if (message.contains('Parsed ') && message.contains('track points')) {
      // Extract point count for unique key
      final pointMatch = RegExp(r'\d+').firstMatch(message);
      final operationKey = 'igc_parse_points_${pointMatch?.group(0) ?? 'unknown'}';
      if (_isRecentDuplicateOperation(operationKey)) {
        _logger.d('[IGC_DUPLICATE_SUPPRESSED] $message | at=logging_service.dart:${StackTrace.current.toString().split('\n')[1].split(':')[2]}');
        return;
      }
    }

    _logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log warnings
  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log errors
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log fatal errors
  static void fatal(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f(message, error: error, stackTrace: stackTrace);
  }

  /// Log database operations with structured format and performance tracking
  static void database(String operation, String message, [dynamic error]) {
    if (error != null) {
      _logger.e('[DB:$operation] $message | error=$error');
    } else {
      _logger.d('[DB:$operation] $message');
    }
  }

  /// Log database query with SQL and performance tracking
  static void databaseQuery(String operation, String sql, Duration duration, {
    int? resultCount,
    Map<String, dynamic>? parameters,
  }) {
    final ms = duration.inMilliseconds;

    // Track in PerformanceMetricsService
    PerformanceMetricsService.trackOperation(
      'db_$operation',
      ms,
      sql: sql,
      resultCount: resultCount,
      metadata: parameters,
    );

    // Only log if slow or sampled
    if (ms > 100 || _shouldLogPerformance('database_query')) {
      structured('DB_QUERY', {
        'operation': operation,
        'duration_ms': ms,
        'result_count': resultCount ?? 0,
        if (ms > 500) 'sql': sql, // Only include SQL for slow queries
        if (parameters != null && parameters.isNotEmpty) 'params': parameters,
      });
    }
  }

  /// Log cache operations with hit/miss tracking
  static void cache(String cacheName, bool hit, {
    String? key,
    int? sizeBytes,
    Duration? lookupTime,
  }) {
    // Track in PerformanceMetricsService
    PerformanceMetricsService.trackCacheOperation(
      cacheName,
      hit,
      sizeBytes: sizeBytes,
      key: key,
    );

    // Only log if miss or slow lookup
    if (!hit || (lookupTime != null && lookupTime.inMilliseconds > 10)) {
      structured('CACHE_OPERATION', {
        'cache': cacheName,
        'hit': hit,
        if (key != null) 'key': key,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
        if (lookupTime != null) 'lookup_ms': lookupTime.inMilliseconds,
      });
    }
  }

  /// Log IGC parsing operations with structured format
  static void igc(String operation, String message, [dynamic error]) {
    if (error != null) {
      _logger.w('[IGC:$operation] $message | error=$error');
    } else {
      _logger.d('[IGC:$operation] $message');
    }
  }

  /// Log UI interactions with structured format
  static void ui(String screen, String action, [String? details]) {
    final message = details != null 
        ? '[UI:$screen] $action | $details'
        : '[UI:$screen] $action';
    _logger.d(message);
  }

  // Performance thresholds in milliseconds, keyed by the operation name passed
  // to [performance]. Local work uses CLAUDE.md's targets; network and
  // user-initiated maintenance work uses the point at which the wait is worth
  // reporting rather than a target it can never meet. Names built at the call
  // site (`'BOM ${state.code} parsing'`, `'CESIUM $metric'`, the
  // `PgeSitesQuery_*` pair) are covered by [_thresholdFor]'s prefix match.
  //
  // This map used to hold ten names, exactly one of which - 'Load flights' - was
  // ever passed to [performance]: a 1761ms database startup and an 11306ms first
  // map load both went unremarked, and 50 of the 51 operations in the codebase
  // had no threshold at all. test/performance_thresholds_test.dart now fails if a
  // call site's operation has none.
  static const Map<String, int> _performanceThresholds = {
    // Startup and screen work.
    'Startup: database': 1000, // >1s to open the database
    'Startup: tables': 500,
    'Load Nearby Sites Data': 1000, // first map content; >1s is the flag
    'Screen navigation': 300,
    'Hot reload': 2000,
    'List scrolling': 16, // 60fps
    // Flights and sites - query targets.
    'Load flights': 200,
    'Load all flights': 200,
    'Load database stats': 200,
    'Statistics Load': 200,
    'Wings Load': 200,
    'Sites Load': 200,
    'SiteBoundsLoaderV2': 200,
    'Optimized sites query': 200,
    'Local sites with PGE JOIN': 200,
    'PgeSitesQuery': 200, // PgeSitesQuery_Bounds / _Search
    'Database Query': 200,
    'database_query': 200,
    'flights loaded': 200,
    'Single flight query': 100,
    'Filter Sites by Distance': 100,
    // Weather parsing and station handling.
    'Station deduplication': 100,
    'FFVL parsing': 500,
    'Pioupiou parsing': 500,
    'AWC_METAR parsing': 500,
    'BOM ': 500, // BOM ${state.code} parsing
    'Get Current Position': 2000,
    // Network work: long by nature, so the flag is well past a target.
    'Catalogue download': 5000,
    'PGE Sites Download': 5000,
    'PGE Sites Import': 3000,
    'Paragliding Earth API': 3000, // also the (Error) / (Failed) names
    'Test ParaglidingEarth API': 3000,
    'Test Cesium token': 3000,
    'Cesium3D Provider Switch': 2000,
    'CESIUM ': 1000, // CESIUM $metric
    // IGC work.
    'IGC file loading': 1000,
    'IGC_FILE_PARSE': 1000,
    'IGC batch import': 3000,
    'Analyze IGC files': 3000,
    'Cleanup orphaned IGC files': 3000,
    // Airspace cache internals - local disk and query work.
    '[AIRSPACE_DB_INIT] ': 500,
    '[BATCH_GEOMETRY_FETCH]': 500,
    '[BATCH_GEOMETRY_FETCH_WITH_CACHE]': 500,
    '[BATCH_GEOMETRY_INSERT]': 500,
    '[GET_GEOMETRY_SLOW]': 1000, // the call site already decided it was slow
    '[PUT_GEOMETRY_SLOW]': 1000,
    '[MEMORY_CACHE_HIT]': 50,
    '[SPATIAL_QUERY_COMPLETE]': 500,
    'Stored airspace geometry': 500,
    'Cleaned expired cache': 500,
    'Clear map cache': 500,
    'Airspace Processing (Error)': 1000,
    // User-initiated maintenance: no target, just an upper bound.
    'Delete all flight data': 5000,
    'Load backup diagnostics': 2000,
    'Re-match flight launches': 10000,
    'Re-match unknown sites': 10000,
    'Recreate database from IGC': 30000,
  };

  /// The threshold for [operation]: exact match first, then the longest matching
  /// prefix, so names assembled at the call site are covered too.
  static int? _thresholdFor(String operation) {
    final exact = _performanceThresholds[operation];
    if (exact != null) return exact;
    int? best;
    var bestLength = -1;
    for (final entry in _performanceThresholds.entries) {
      if (entry.key.length > bestLength && operation.startsWith(entry.key)) {
        best = entry.value;
        bestLength = entry.key.length;
      }
    }
    return best;
  }

  /// WARNING, CRITICAL, or null when [operation] at [ms] is inside its
  /// threshold. The warning path and the test both go through here.
  static String? _thresholdSeverity(String operation, int ms) {
    final threshold = _thresholdFor(operation);
    if (threshold == null || ms <= threshold) return null;
    return ms > threshold * 2 ? 'CRITICAL' : 'WARNING';
  }

  /// The threshold [operation] resolves to, or null if it has none.
  @visibleForTesting
  static int? thresholdForTest(String operation) => _thresholdFor(operation);

  /// The warning level [operation] at [ms] warrants, or null if none.
  @visibleForTesting
  static String? thresholdSeverityForTest(String operation, int ms) =>
      _thresholdSeverity(operation, ms);

  /// Log performance metrics with structured format and automatic threshold warnings
  static void performance(String operation, Duration duration, [String? details]) {
    final ms = duration.inMilliseconds;

    // Track in PerformanceMetricsService for percentile tracking
    PerformanceMetricsService.trackOperation(
      operation,
      ms,
      metadata: details != null ? {'details': details} : null,
    );

    // Build base message
    final message = details != null
        ? '[PERF] $operation | ${ms}ms | $details'
        : '[PERF] $operation | ${ms}ms';

    // Check if operation exceeds performance threshold
    final threshold = _thresholdFor(operation);
    final severity = _thresholdSeverity(operation, ms);
    if (severity != null) {
      final detailsStr = details != null ? ' | $details' : '';
      _logger.w('[PERF_THRESHOLD_$severity] $operation | actual=${ms}ms | target=${threshold}ms$detailsStr');
    }

    // Reduce duplicate [PERF] logs - only log if significant
    if (threshold == null || ms > threshold || _shouldLogPerformance(operation)) {
      _logger.d(message);
    }
  }

  /// Determine if performance metric should be logged to reduce duplicates
  static bool _shouldLogPerformance(String operation) {
    // Log every Nth performance metric for high-frequency operations
    const highFrequencyOps = {
      'database_query': 10,
      'cache_lookup': 20,
      'widget_rebuild': 50,
    };

    final frequency = highFrequencyOps[operation];
    if (frequency != null) {
      _incrementCounter(operation);
      return _operationCounters[operation]! % frequency == 0;
    }

    return true; // Log all other operations
  }

  /// Increment counter with bounds checking to prevent memory leak
  static void _incrementCounter(String operation) {
    // Check if we need to clean up old entries
    if (_operationCounters.length >= _maxCounterEntries &&
        !_operationCounters.containsKey(operation)) {
      // Remove oldest entries (clear 25% to avoid frequent cleanup)
      final toRemove = _operationCounters.keys
          .take(_maxCounterEntries ~/ 4)
          .toList();
      for (final key in toRemove) {
        _operationCounters.remove(key);
      }
    }

    _operationCounters[operation] = (_operationCounters[operation] ?? 0) + 1;
  }

  /// Log structured data with key-value pairs for better Claude parsing
  static void structured(String category, Map<String, dynamic> data) {
    // Skip expensive operations in production for non-critical logs
    if (kReleaseMode && _isNonCriticalStructuredLog(category)) {
      return;
    }

    final pairs = data.entries
        .map((e) => '${e.key}=${_formatValue(e.value)}')
        .join(' | ');

    // Release builds are gated at Level.warning, so an info-level structured log
    // never reaches logcat - a release install emits nothing from our own code at
    // all. A few categories are worth keeping in production, and warning is the
    // only level that survives. These are diagnostics rather than problems; the
    // level is a transport, not a severity claim.
    if (kReleaseMode && _releaseVisibleCategories.contains(category)) {
      _logger.w('[$category] $pairs');
      return;
    }
    _logger.i('[$category] $pairs');
  }

  /// Structured categories kept in release builds. Keep this list short - every
  /// entry is noise in production logs, and the value is in being able to answer
  /// one specific question about a build you cannot attach a debugger to.
  ///
  /// API_KEYS_STATUS answers "did this build get its --dart-define secrets?",
  /// which is otherwise unanswerable for a Play-delivered install: the keys are
  /// compile-time constants and a build without them fails silently, with
  /// airspace overlays and 3D simply empty.
  static const Set<String> _releaseVisibleCategories = {'API_KEYS_STATUS'};

  /// Lazy evaluation version of structured logging - only builds data if logging enabled
  static void structuredLazy(String category, Map<String, dynamic> Function() dataBuilder) {
    // Skip expensive operations in production for non-critical logs
    if (kReleaseMode && _isNonCriticalStructuredLog(category)) {
      return;
    }

    // Only build the expensive data if we're actually going to log it. Release
    // visible categories are exempt: the level check would skip them in release,
    // which is exactly where they are wanted.
    if (Logger.level.index <= Level.info.index ||
        _releaseVisibleCategories.contains(category)) {
      final data = dataBuilder();
      structured(category, data);
    }
  }

  /// Check if this is a non-critical structured log that can be skipped in production
  static bool _isNonCriticalStructuredLog(String category) {
    // Skip verbose performance logs in production
    const nonCriticalCategories = {
      'DIRECT_POLYGON_FETCH',
      'DIRECT_POLYGON_COMPLETE',
      'SPATIAL_GEOJSON_FETCH',
      'GEOJSON_MODE_COMPLETE',
      'DIRECT_CLIPPING_PERFORMANCE',
      'BATCH_GEOMETRY_FETCH',
      'SPATIAL_QUERY_COMPLETE',
      'SPATIAL_VIEWPORT_QUERY',
      'DIRECT_POLYGON_PROCESSING',
    };

    return nonCriticalCategories.contains(category);
  }

  /// Log operation summary with results
  static void summary(String operation, Map<String, dynamic> results) {
    final pairs = results.entries
        .map((e) => '${e.key}=${_formatValue(e.value)}')
        .join(' | ');
    _logger.i('[SUMMARY:$operation] $pairs');
  }

  /// Log user action with context
  static void action(String screen, String action, [Map<String, dynamic>? context]) {
    if (context != null && context.isNotEmpty) {
      final pairs = context.entries
          .map((e) => '${e.key}=${_formatValue(e.value)}')
          .join(' | ');
      _logger.i('[ACTION:$screen] $action | $pairs');
    } else {
      _logger.i('[ACTION:$screen] $action');
    }
  }

  /// Log metric value with unit
  static void metric(String name, num value, String unit, [String? category]) {
    final cat = category != null ? '[$category] ' : '';
    _logger.d('$cat[METRIC] $name=$value$unit');
  }

  /// Helper to format values for structured logging
  static String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is double) return value.toStringAsFixed(2);
    if (value is Duration) return '${value.inMilliseconds}ms';
    if (value is DateTime) return value.toIso8601String();
    if (value is List) return 'List[${value.length}]';
    if (value is Map) return 'Map[${value.length}]';
    return value.toString();
  }
  
  /// Start a new operation with correlation ID
  static String startOperation(String type) {
    _incrementCounter(type);
    final count = _operationCounters[type] ?? 1;
    final id = '${type.toLowerCase()}_${count.toString().padLeft(3, '0')}';
    _currentOperationId = id;
    _logger.i('[WORKFLOW:$type] started | id=$id');
    return id;
  }
  
  /// End current operation
  static void endOperation(String type, {Map<String, dynamic>? results}) {
    if (_currentOperationId != null) {
      final pairs = results?.entries
          .map((e) => '${e.key}=${_formatValue(e.value)}')
          .join(' | ') ?? '';
      _logger.i('[WORKFLOW:$type] completed | id=$_currentOperationId${pairs.isNotEmpty ? ' | $pairs' : ''}');
      _currentOperationId = null;
    }
  }
  
  /// Log with current operation context
  static void operation(String message, [Map<String, dynamic>? data]) {
    final opId = _currentOperationId != null ? ' | op=$_currentOperationId' : '';
    final pairs = data?.entries
        .map((e) => '${e.key}=${_formatValue(e.value)}')
        .join(' | ') ?? '';
    _logger.d('$message$opId${pairs.isNotEmpty ? ' | $pairs' : ''}');
  }
}

/// Extension methods for easier logging from any context
extension LoggingExtensions on Object {
  void logDebug(String message) => LoggingService.debug('$runtimeType: $message');
  void logInfo(String message) => LoggingService.info('$runtimeType: $message');
  void logWarning(String message) => LoggingService.warning('$runtimeType: $message');
  void logError(String message, [dynamic error]) => LoggingService.error('$runtimeType: $message', error);
}