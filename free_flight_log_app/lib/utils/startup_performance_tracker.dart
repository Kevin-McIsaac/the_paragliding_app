import 'dart:collection';

/// Tracks performance metrics during app startup
class StartupPerformanceTracker {
  static final StartupPerformanceTracker _instance = StartupPerformanceTracker._internal();
  factory StartupPerformanceTracker() => _instance;
  StartupPerformanceTracker._internal();

  final Stopwatch _mainStopwatch = Stopwatch();
  final LinkedHashMap<String, Duration> _measurements = LinkedHashMap();
  final LinkedHashMap<String, DateTime> _timestamps = LinkedHashMap();
  DateTime? _appStartTime;

  /// Start tracking app initialization
  void startTracking() {
    _appStartTime = DateTime.now();
    _mainStopwatch.start();
    _measurements.clear();
    _timestamps.clear();
    recordTimestamp('App Start');
  }

  /// Record a timestamp for an event
  void recordTimestamp(String event) {
    _timestamps[event] = DateTime.now();
  }

  /// Start measuring a specific operation
  Stopwatch startMeasurement(String operation) {
    final stopwatch = Stopwatch()..start();
    return stopwatch;
  }

  /// Complete a measurement
  void completeMeasurement(String operation, Stopwatch stopwatch) {
    stopwatch.stop();
    _measurements[operation] = stopwatch.elapsed;
    recordTimestamp('$operation Complete');
  }

  /// Record a duration directly
  void recordDuration(String operation, Duration duration) {
    _measurements[operation] = duration;
  }

  /// Get total startup time
  Duration get totalStartupTime => _mainStopwatch.elapsed;

  /// Stop tracking and generate report
  String generateReport() {
    _mainStopwatch.stop();
    
    final buffer = StringBuffer();
    buffer.writeln('\n════════════════════════════════════════════════════════════════');
    buffer.writeln('                    STARTUP PERFORMANCE REPORT                   ');
    buffer.writeln('════════════════════════════════════════════════════════════════');
    
    if (_appStartTime != null) {
      buffer.writeln('App Start Time: ${_appStartTime!.toIso8601String()}');
    }
    
    buffer.writeln('Total Startup Time: ${_formatDuration(totalStartupTime)}');
    buffer.writeln('');
    
    buffer.writeln('Detailed Measurements:');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    
    // Calculate the longest operation name for formatting
    int maxLength = _measurements.keys.fold(0, (max, key) => key.length > max ? key.length : max);
    maxLength = maxLength < 30 ? 30 : maxLength;
    
    // Sort by duration (longest first) for easier identification of bottlenecks
    final sortedEntries = _measurements.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    for (final entry in sortedEntries) {
      final percentage = (entry.value.inMicroseconds / totalStartupTime.inMicroseconds * 100);
      final paddedName = entry.key.padRight(maxLength);
      final duration = _formatDuration(entry.value).padLeft(10);
      final bar = _generateBar(percentage);
      
      buffer.writeln('$paddedName $duration  $bar ${percentage.toStringAsFixed(1)}%');
    }
    
    buffer.writeln('');
    buffer.writeln('Event Timeline:');
    buffer.writeln('─────────────────────────────────────────────────────────────────');
    
    DateTime? firstTimestamp;
    for (final entry in _timestamps.entries) {
      firstTimestamp ??= entry.value;
      final elapsed = entry.value.difference(firstTimestamp);
      final elapsedStr = _formatDuration(elapsed).padLeft(10);
      buffer.writeln('$elapsedStr  ${entry.key}');
    }
    
    buffer.writeln('════════════════════════════════════════════════════════════════');
    
    // Performance summary
    buffer.writeln('\nPerformance Summary:');
    if (totalStartupTime.inMilliseconds < 100) {
      buffer.writeln('✅ EXCELLENT: App started in under 100ms');
    } else if (totalStartupTime.inMilliseconds < 500) {
      buffer.writeln('✅ GOOD: App started in under 500ms');
    } else if (totalStartupTime.inMilliseconds < 1000) {
      buffer.writeln('⚠️  ACCEPTABLE: App started in under 1 second');
    } else {
      buffer.writeln('❌ SLOW: App took over 1 second to start');
    }
    
    // Identify bottlenecks
    if (sortedEntries.isNotEmpty) {
      buffer.writeln('\nTop Bottlenecks:');
      for (int i = 0; i < sortedEntries.length && i < 3; i++) {
        final entry = sortedEntries[i];
        if (entry.value.inMilliseconds > 50) {
          buffer.writeln('  ${i + 1}. ${entry.key}: ${_formatDuration(entry.value)}');
        }
      }
    }
    
    buffer.writeln('════════════════════════════════════════════════════════════════');
    
    return buffer.toString();
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds == 0) {
      return '${duration.inMicroseconds}μs';
    } else if (duration.inSeconds == 0) {
      return '${duration.inMilliseconds}ms';
    } else {
      return '${duration.inSeconds}.${(duration.inMilliseconds % 1000).toString().padLeft(3, '0')}s';
    }
  }

  /// Generate a visual bar for percentage
  String _generateBar(double percentage) {
    final width = 20;
    final filled = (percentage / 100 * width).round();
    final bar = '█' * filled + '░' * (width - filled);
    return '[$bar]';
  }

  /// Clear all measurements
  void reset() {
    _mainStopwatch.reset();
    _measurements.clear();
    _timestamps.clear();
    _appStartTime = null;
  }
}