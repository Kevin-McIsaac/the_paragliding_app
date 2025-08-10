import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../services/logging_service.dart';
import '../../../config/cesium_config.dart';
import 'cesium_webview_controller.dart';

/// Manages memory for the Cesium 3D map
/// 
/// This class handles:
/// - Memory monitoring
/// - Automatic cleanup
/// - Quality adjustments based on memory pressure
/// - Performance optimization
class CesiumMemoryManager {
  final CesiumWebViewController _webViewController;
  Timer? _memoryMonitorTimer;
  Timer? _cleanupTimer;
  bool _isDisposed = false;
  int _highMemoryCount = 0;
  static const int _maxHighMemoryEvents = 3;
  
  CesiumMemoryManager(this._webViewController);
  
  /// Starts memory monitoring
  void startMonitoring() {
    if (_isDisposed) return;
    
    // Only monitor in debug mode to avoid overhead
    if (!kDebugMode) return;
    
    LoggingService.debug('CesiumMemoryManager: Starting memory monitoring');
    
    _memoryMonitorTimer = Timer.periodic(
      CesiumConfig.memoryMonitorInterval,
      (_) => _checkMemoryUsage(),
    );
    
    // Start periodic cleanup
    _startPeriodicCleanup();
  }
  
  /// Starts periodic memory cleanup
  void _startPeriodicCleanup() {
    if (_isDisposed) return;
    
    _cleanupTimer = Timer.periodic(
      CesiumConfig.memoryCleanupInterval,
      (_) => _performCleanup(),
    );
  }
  
  /// Checks current memory usage
  Future<void> _checkMemoryUsage() async {
    if (_isDisposed || _webViewController.isDisposed) {
      _memoryMonitorTimer?.cancel();
      return;
    }
    
    // Check memory usage via JavaScript
    final result = await _webViewController.evaluateJavascript(source: '''
      if (typeof checkMemory === 'function') {
        const usage = checkMemory();
        if (usage) {
          cesiumLog.debug('Memory: ' + usage.used + 'MB / ' + usage.total + 'MB (limit: ' + usage.limit + 'MB)');
          return usage;
        }
      }
      return null;
    ''');
    
    if (result != null && result is Map) {
      final usedMB = result['used'] ?? 0;
      final totalMB = result['total'] ?? 0;
      
      // Check for high memory usage
      if (usedMB > totalMB * 0.8) {
        _highMemoryCount++;
        LoggingService.warning('CesiumMemoryManager: High memory usage detected: ${usedMB}MB');
        
        if (_highMemoryCount >= _maxHighMemoryEvents) {
          await _handleHighMemoryPressure();
          _highMemoryCount = 0;
        }
      } else {
        // Reset counter if memory is normal
        _highMemoryCount = 0;
      }
    }
  }
  
  /// Performs routine memory cleanup
  Future<void> _performCleanup() async {
    if (_isDisposed || _webViewController.isDisposed) return;
    
    await _webViewController.evaluateJavascript(source: '''
      if (viewer && viewer.scene && viewer.scene.globe) {
        // Check memory usage via performance API
        if (window.performance && window.performance.memory) {
          const memoryUsage = window.performance.memory.usedJSHeapSize;
          if (memoryUsage > 100 * 1024 * 1024) {  // If over 100MB
            cesiumLog.debug('Routine cleanup: Memory at ' + (memoryUsage / 1024 / 1024).toFixed(1) + 'MB');
            
            // Clear unused primitives and entities
            viewer.scene.primitives.removeAll();
            viewer.entities.removeAll();
            
            // Force garbage collection if available
            if (window.gc) {
              window.gc();
            }
          }
        }
        
        // Monitor tile count for cleanup
        if (viewer.scene.globe._surface && viewer.scene.globe._surface._tilesToRender) {
          const tileCount = viewer.scene.globe._surface._tilesToRender.length;
          if (tileCount > 25) {
            cesiumLog.debug('Routine cleanup: High tile count ' + tileCount);
            // Temporarily increase screen space error to reduce tile count
            viewer.scene.globe.maximumScreenSpaceError = 6;
            
            // Reset after a delay
            setTimeout(() => {
              if (viewer && viewer.scene && viewer.scene.globe) {
                viewer.scene.globe.maximumScreenSpaceError = ${CesiumConfig.maximumScreenSpaceError};
              }
            }, 5000);
          }
        }
      }
    ''');
  }
  
  /// Handles high memory pressure situations
  Future<void> _handleHighMemoryPressure() async {
    if (_isDisposed || _webViewController.isDisposed) return;
    
    LoggingService.warning('CesiumMemoryManager: Handling high memory pressure');
    
    // Use the WebView controller's memory pressure handler
    await _webViewController.handleMemoryPressure();
    
    // Additional aggressive cleanup
    await _webViewController.evaluateJavascript(source: '''
      if (viewer && viewer.scene) {
        // Stop all animations
        viewer.scene.animations.removeAll();
        
        // Clear all data sources
        viewer.dataSources.removeAll();
        
        // Reduce rendering quality temporarily
        viewer.scene.globe.maximumScreenSpaceError = 10;
        viewer.scene.maximumTextureSize = 256;
        viewer.scene.globe.tileCacheSize = 3;
        viewer.scene.globe.maximumMemoryUsage = 32;
        
        // Disable features temporarily
        viewer.scene.globe.enableLighting = false;
        viewer.scene.globe.showGroundAtmosphere = false;
        viewer.scene.fog.enabled = false;
        
        cesiumLog.warning('Applied emergency memory reduction settings');
        
        // Restore settings after 10 seconds
        setTimeout(() => {
          if (viewer && viewer.scene && viewer.scene.globe) {
            viewer.scene.globe.maximumScreenSpaceError = ${CesiumConfig.maximumScreenSpaceError};
            viewer.scene.maximumTextureSize = ${CesiumConfig.maximumTextureSize};
            viewer.scene.globe.tileCacheSize = ${CesiumConfig.tileCacheSize};
            viewer.scene.globe.maximumMemoryUsage = ${CesiumConfig.maximumMemoryUsageMB};
            cesiumLog.info('Restored normal quality settings');
          }
        }, 10000);
      }
    ''');
  }
  
  /// Handles app lifecycle pause
  void handleAppPause() {
    if (_isDisposed) return;
    
    // Pause monitoring
    _memoryMonitorTimer?.cancel();
    _cleanupTimer?.cancel();
    
    // Pause WebView timers
    _webViewController.pauseTimers();
    
    LoggingService.debug('CesiumMemoryManager: App paused - monitoring stopped');
  }
  
  /// Handles app lifecycle resume
  void handleAppResume() {
    if (_isDisposed) return;
    
    // Resume WebView timers
    _webViewController.resumeTimers();
    
    // Restart monitoring
    startMonitoring();
    
    LoggingService.debug('CesiumMemoryManager: App resumed - monitoring restarted');
  }
  
  /// Handles system memory warning
  Future<void> handleMemoryWarning() async {
    if (_isDisposed) return;
    
    LoggingService.warning('CesiumMemoryManager: System memory warning received');
    
    // Immediately handle as high pressure
    await _handleHighMemoryPressure();
  }
  
  /// Disposes the memory manager
  void dispose() {
    if (_isDisposed) return;
    
    _isDisposed = true;
    _memoryMonitorTimer?.cancel();
    _cleanupTimer?.cancel();
    
    LoggingService.debug('CesiumMemoryManager: Disposed');
  }
}