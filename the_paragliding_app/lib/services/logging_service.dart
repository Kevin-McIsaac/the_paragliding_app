import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'claude_log_printer.dart';

/// Centralized logging service for The Paragliding App application
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();
  
  // Operation tracking
  static String? _currentOperationId;
  static final Map<String, int> _operationCounters = {};
  
  // Duplicate operation detection
  static final Set<String> _recentOperations = <String>{};

  // Claude-optimized logger with enhanced readability and navigation
  static final Logger _logger = Logger(
    level: kDebugMode ? Level.debug : Level.warning,
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
    // Suppress duplicate IGC parsing operations  
    if (message.contains('Successfully parsed date:') || 
        message.contains('Parsed ') && message.contains('track points')) {
      final operationKey = 'igc_parse_${message.hashCode % 1000}';
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

  /// Log database operations with structured format
  static void database(String operation, String message, [dynamic error]) {
    if (error != null) {
      _logger.e('[DB:$operation] $message | error=$error');
    } else {
      _logger.d('[DB:$operation] $message');
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

  // Performance thresholds from CLAUDE.md guidelines (in milliseconds)
  static final Map<String, int> _performanceThresholds = {
    'Database Query': 200,
    'Single flight query': 100,
    'Load all flights': 200,
    'Load flights': 200,
    'IGC file loading': 1000,
    'Database startup': 300,
    'Hot reload': 2000,
    'Screen navigation': 300,
    'List scrolling': 16, // 60fps
    'database_query': 200,
    'flights loaded': 200,
  };

  /// Log performance metrics with structured format and automatic threshold warnings
  static void performance(String operation, Duration duration, [String? details]) {
    final ms = duration.inMilliseconds;

    // Build base message
    final message = details != null
        ? '[PERF] $operation | ${ms}ms | $details'
        : '[PERF] $operation | ${ms}ms';

    // Check if operation exceeds performance threshold
    final threshold = _performanceThresholds[operation];
    if (threshold != null && ms > threshold) {
      final severity = ms > threshold * 2 ? 'CRITICAL' : 'WARNING';
      final detailsStr = details != null ? ' | $details' : '';
      _logger.w('[PERF_THRESHOLD_$severity] $operation | actual=${ms}ms | target=${threshold}ms$detailsStr');
    }

    // Log normal performance metric
    _logger.d(message);
  }

  /// Log structured data with key-value pairs for better Claude parsing
  static void structured(String category, Map<String, dynamic> data) {
    // Skip expensive operations in production for non-critical logs
    if (!kDebugMode && _isNonCriticalStructuredLog(category)) {
      return;
    }

    final pairs = data.entries
        .map((e) => '${e.key}=${_formatValue(e.value)}')
        .join(' | ');
    _logger.i('[$category] $pairs');
  }

  /// Lazy evaluation version of structured logging - only builds data if logging enabled
  static void structuredLazy(String category, Map<String, dynamic> Function() dataBuilder) {
    // Skip expensive operations in production for non-critical logs
    if (!kDebugMode && _isNonCriticalStructuredLog(category)) {
      return;
    }

    // Only build the expensive data if we're actually going to log it
    if (Logger.level.index <= Level.info.index) {
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
    final count = (_operationCounters[type] ?? 0) + 1;
    _operationCounters[type] = count;
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