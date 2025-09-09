import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/logging_service.dart';

/// Utility class for monitoring app performance metrics
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  // Configuration constants
  static const int _maxWidgetEntries = 100;
  static const int _maxOperationEntries = 50;
  static const Duration _cleanupInterval = Duration(hours: 1);
  static const Duration _entryMaxAge = Duration(hours: 2);
  
  // Track widget rebuild counts
  static final Map<String, int> _widgetRebuildCounts = {};
  static final Map<String, DateTime> _lastRebuildTime = {};
  
  // Track operation timings
  static final Map<String, DateTime> _operationStarts = {};
  
  // Cleanup tracking
  static DateTime _lastCleanup = DateTime.now();
  
  /// Get current memory usage in MB
  static double getMemoryUsageMB() {
    if (!kDebugMode) return 0.0;
    
    try {
      final info = ProcessInfo.currentRss;
      return info / (1024 * 1024); // Convert bytes to MB
    } catch (e) {
      // Log error but return safe default to prevent crashes
      LoggingService.error('PerformanceMonitor: Failed to get memory usage', e);
      return 0.0;
    }
  }
  
  /// Track widget rebuilds and log if frequency is high
  static void trackWidgetRebuild(String widgetName) {
    if (!kDebugMode) return;
    
    // Perform cleanup if needed
    _performCleanupIfNeeded();
    
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
    if (startTime == null) {
      LoggingService.warning('PerformanceMonitor: Attempted to end operation "$operationName" that was not started');
      return null;
    }
    
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
  
  /// Perform cleanup of old entries if needed
  static void _performCleanupIfNeeded() {
    final now = DateTime.now();
    
    // Check if cleanup is needed
    if (now.difference(_lastCleanup) < _cleanupInterval && 
        _widgetRebuildCounts.length < _maxWidgetEntries &&
        _operationStarts.length < _maxOperationEntries) {
      return;
    }
    
    _performCleanup();
    _lastCleanup = now;
  }
  
  /// Perform cleanup of old entries
  static void _performCleanup() {
    final now = DateTime.now();
    
    // Remove old widget rebuild entries
    final oldWidgetKeys = <String>[];
    for (final entry in _lastRebuildTime.entries) {
      if (now.difference(entry.value) > _entryMaxAge) {
        oldWidgetKeys.add(entry.key);
      }
    }
    
    for (final key in oldWidgetKeys) {
      _widgetRebuildCounts.remove(key);
      _lastRebuildTime.remove(key);
    }
    
    // Remove old operation entries
    final oldOperationKeys = <String>[];
    for (final entry in _operationStarts.entries) {
      if (now.difference(entry.value) > _entryMaxAge) {
        oldOperationKeys.add(entry.key);
      }
    }
    
    for (final key in oldOperationKeys) {
      _operationStarts.remove(key);
    }
    
    // If still too many entries, remove oldest ones
    if (_widgetRebuildCounts.length > _maxWidgetEntries) {
      final sortedWidgets = _lastRebuildTime.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      final toRemove = sortedWidgets.take(_widgetRebuildCounts.length - _maxWidgetEntries);
      for (final entry in toRemove) {
        _widgetRebuildCounts.remove(entry.key);
        _lastRebuildTime.remove(entry.key);
      }
    }
    
    if (_operationStarts.length > _maxOperationEntries) {
      final sortedOperations = _operationStarts.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      final toRemove = sortedOperations.take(_operationStarts.length - _maxOperationEntries);
      for (final entry in toRemove) {
        _operationStarts.remove(entry.key);
      }
    }
    
    if (oldWidgetKeys.isNotEmpty || oldOperationKeys.isNotEmpty) {
      LoggingService.debug('PerformanceMonitor: Cleaned up ${oldWidgetKeys.length} widget entries and ${oldOperationKeys.length} operation entries');
    }
  }
  
  /// Reset all counters (useful for testing)
  static void reset() {
    _widgetRebuildCounts.clear();
    _lastRebuildTime.clear();
    _operationStarts.clear();
    _lastCleanup = DateTime.now();
  }
}