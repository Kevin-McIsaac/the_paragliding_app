import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'claude_log_printer.dart';

/// Centralized logging service for Free Flight Log application
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();
  
  // Operation tracking
  static String? _currentOperationId;
  static final Map<String, int> _operationCounters = {};

  // Claude-optimized logger with enhanced readability and navigation
  static final Logger _logger = Logger(
    level: kDebugMode ? Level.debug : Level.warning,
    printer: kDebugMode 
      ? ClaudeLogPrinter() // Custom printer for Claude Code
      : PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 120,
          colors: false,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
        ),
  );

  /// Log debug information
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log general information
  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
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

  /// Log performance metrics with structured format
  static void performance(String operation, Duration duration, [String? details]) {
    final message = details != null 
        ? '[PERF] $operation | ${duration.inMilliseconds}ms | $details'
        : '[PERF] $operation | ${duration.inMilliseconds}ms';
    _logger.d(message);
  }

  /// Log structured data with key-value pairs for better Claude parsing
  static void structured(String category, Map<String, dynamic> data) {
    final pairs = data.entries
        .map((e) => '${e.key}=${_formatValue(e.value)}')
        .join(' | ');
    _logger.i('[$category] $pairs');
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
    _logger.d('${cat}[METRIC] $name=$value$unit');
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