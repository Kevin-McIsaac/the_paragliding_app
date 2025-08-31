import '../services/logging_service.dart';

/// Simple performance tracking for debugging
class StartupPerformanceTracker {
  static final StartupPerformanceTracker _instance = StartupPerformanceTracker._internal();
  factory StartupPerformanceTracker() => _instance;
  StartupPerformanceTracker._internal();

  /// Start tracking a measurement
  Stopwatch startMeasurement(String operation) {
    final stopwatch = Stopwatch()..start();
    LoggingService.debug('PERF: Started $operation');
    return stopwatch;
  }

  /// Complete a measurement
  void completeMeasurement(String operation, Stopwatch stopwatch) {
    stopwatch.stop();
    LoggingService.performance(operation, stopwatch.elapsed);
  }

  /// Record a simple event
  void recordEvent(String event) {
    LoggingService.debug('EVENT: $event');
  }
}