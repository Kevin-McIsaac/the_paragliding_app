import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/logging_service.dart';

/// Utility class for monitoring app performance metrics
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  // Track widget rebuild counts
  static final Map<String, int> _widgetRebuildCounts = {};
  static final Map<String, DateTime> _lastRebuildTime = {};
  
  // Track operation timings
  static final Map<String, DateTime> _operationStarts = {};
  
  /// Get current memory usage in MB
  static double getMemoryUsageMB() {
    if (!kDebugMode) return 0.0;
    
    try {
      final info = ProcessInfo.currentRss;
      return info / (1024 * 1024); // Convert bytes to MB
    } catch (e) {
      return 0.0;
    }
  }
  
  /// Track widget rebuilds and log if frequency is high
  static void trackWidgetRebuild(String widgetName) {
    if (!kDebugMode) return;
    
    final now = DateTime.now();
    final count = (_widgetRebuildCounts[widgetName] ?? 0) + 1;
    _widgetRebuildCounts[widgetName] = count;
    
    // Check rebuild frequency
    final lastTime = _lastRebuildTime[widgetName];
    if (lastTime != null) {
      final timeSinceLastRebuild = now.difference(lastTime);
      
      // Log if rebuilding too frequently (more than once per 100ms)
      if (timeSinceLastRebuild.inMilliseconds < 100) {
        LoggingService.warning('[PERF_WARNING] Widget $widgetName rebuilding rapidly', {
          'rebuild_count': count,
          'time_since_last_ms': timeSinceLastRebuild.inMilliseconds,
        });
      }
    }
    
    _lastRebuildTime[widgetName] = now;
    
    // Log every 10 rebuilds
    if (count % 10 == 0) {
      LoggingService.metric('widget_rebuilds', count, 'rebuilds', widgetName);
    }
  }
  
  /// Start timing an operation
  static void startOperation(String operationName) {
    if (!kDebugMode) return;
    _operationStarts[operationName] = DateTime.now();
  }
  
  /// End timing an operation and log performance
  static Duration? endOperation(String operationName, {Map<String, dynamic>? metadata}) {
    if (!kDebugMode) return null;
    
    final startTime = _operationStarts.remove(operationName);
    if (startTime == null) return null;
    
    final duration = DateTime.now().difference(startTime);
    
    // Log with memory usage
    final memoryMB = getMemoryUsageMB();
    final perfData = {
      'duration_ms': duration.inMilliseconds,
      'memory_mb': memoryMB.toStringAsFixed(1),
      ...?metadata,
    };
    
    LoggingService.structured('PERF_OP', {
      'operation': operationName,
      ...perfData,
    });
    
    // Warn if operation took too long
    if (duration.inMilliseconds > 1000) {
      LoggingService.warning('[PERF_SLOW] Operation $operationName took ${duration.inMilliseconds}ms');
    }
    
    return duration;
  }
  
  /// Log current memory usage
  static void logMemoryUsage(String context) {
    if (!kDebugMode) return;
    
    final memoryMB = getMemoryUsageMB();
    LoggingService.metric('memory_usage', memoryMB, 'MB', context);
  }
  
  /// Log performance summary
  static void logPerformanceSummary() {
    if (!kDebugMode) return;
    
    final memoryMB = getMemoryUsageMB();
    
    LoggingService.summary('PERFORMANCE', {
      'memory_mb': memoryMB.toStringAsFixed(1),
      'total_widgets_tracked': _widgetRebuildCounts.length,
      'total_rebuilds': _widgetRebuildCounts.values.fold(0, (a, b) => a + b),
    });
    
    // Log top rebuilding widgets
    if (_widgetRebuildCounts.isNotEmpty) {
      final sortedWidgets = _widgetRebuildCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final top3 = sortedWidgets.take(3).map((e) => '${e.key}:${e.value}').join(', ');
      LoggingService.info('[PERF_REBUILDS] Top widgets: $top3');
    }
  }
  
  /// Reset all counters (useful for testing)
  static void reset() {
    _widgetRebuildCounts.clear();
    _lastRebuildTime.clear();
    _operationStarts.clear();
  }
}