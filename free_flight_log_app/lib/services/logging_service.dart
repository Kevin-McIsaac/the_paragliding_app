import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

/// Centralized logging service for Free Flight Log application
class LoggingService {
  static final LoggingService _instance = LoggingService._internal();
  factory LoggingService() => _instance;
  LoggingService._internal();

  static final Logger _logger = Logger(
    level: kDebugMode ? Level.debug : Level.warning, // Reduce logging in production
    printer: PrettyPrinter(
      methodCount: kDebugMode ? 2 : 0, // Disable stack traces in production
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: kDebugMode, // Disable emojis in production for performance
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

  /// Log database operations
  static void database(String operation, String message, [dynamic error]) {
    if (error != null) {
      _logger.e('DB[$operation]: $message', error: error);
    } else {
      _logger.d('DB[$operation]: $message');
    }
  }

  /// Log IGC parsing operations
  static void igc(String operation, String message, [dynamic error]) {
    if (error != null) {
      _logger.w('IGC[$operation]: $message', error: error);
    } else {
      _logger.d('IGC[$operation]: $message');
    }
  }

  /// Log UI interactions for debugging
  static void ui(String screen, String action, [String? details]) {
    final message = details != null ? '$action - $details' : action;
    _logger.d('UI[$screen]: $message');
  }

  /// Log performance metrics (debug level to reduce production overhead)
  static void performance(String operation, Duration duration, [String? details]) {
    final message = details != null 
        ? '$operation completed in ${duration.inMilliseconds}ms - $details'
        : '$operation completed in ${duration.inMilliseconds}ms';
    _logger.d('PERF: $message'); // Changed from info to debug
  }
}

/// Extension methods for easier logging from any context
extension LoggingExtensions on Object {
  void logDebug(String message) => LoggingService.debug('$runtimeType: $message');
  void logInfo(String message) => LoggingService.info('$runtimeType: $message');
  void logWarning(String message) => LoggingService.warning('$runtimeType: $message');
  void logError(String message, [dynamic error]) => LoggingService.error('$runtimeType: $message', error);
}