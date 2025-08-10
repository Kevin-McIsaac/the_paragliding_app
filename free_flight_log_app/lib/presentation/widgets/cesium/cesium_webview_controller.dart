import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../../services/logging_service.dart';

/// Manages the WebView controller for Cesium 3D map
/// 
/// This class handles:
/// - WebView lifecycle management
/// - JavaScript execution
/// - Error handling and recovery
/// - WebView disposal
class CesiumWebViewController {
  InAppWebViewController? _controller;
  bool _isDisposed = false;
  Timer? _disposeTimer;
  
  /// Gets the current WebView controller
  InAppWebViewController? get controller => _controller;
  
  /// Whether the controller has been disposed
  bool get isDisposed => _isDisposed;
  
  /// Sets the WebView controller
  void setController(InAppWebViewController controller) {
    if (_isDisposed) return;
    _controller = controller;
    LoggingService.debug('CesiumWebViewController: Controller set');
  }
  
  /// Executes JavaScript code in the WebView
  Future<dynamic> evaluateJavascript({
    required String source,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_isDisposed || _controller == null) return null;
    
    try {
      return await _controller!
          .evaluateJavascript(source: source)
          .timeout(timeout, onTimeout: () {
        LoggingService.debug('CesiumWebViewController: JavaScript execution timed out');
        return null;
      });
    } catch (e) {
      LoggingService.debug('CesiumWebViewController: JavaScript execution error: $e');
      return null;
    }
  }
  
  /// Reloads the WebView
  Future<void> reload() async {
    if (_isDisposed || _controller == null) return;
    
    try {
      await _controller!.reload();
      LoggingService.debug('CesiumWebViewController: Reloaded');
    } catch (e) {
      LoggingService.error('CesiumWebViewController', 'Reload failed: $e');
    }
  }
  
  /// Stops loading the WebView
  Future<void> stopLoading() async {
    if (_isDisposed || _controller == null) return;
    
    try {
      await _controller!.stopLoading().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          LoggingService.debug('CesiumWebViewController: Stop loading timed out');
        },
      );
    } catch (e) {
      LoggingService.debug('CesiumWebViewController: Stop loading error: $e');
    }
  }
  
  /// Clears the WebView cache
  Future<void> clearCache() async {
    if (_isDisposed || _controller == null) return;
    
    try {
      await _controller!.clearCache().timeout(
        const Duration(milliseconds: 500),
        onTimeout: () {
          LoggingService.debug('CesiumWebViewController: Clear cache timed out');
        },
      );
    } catch (e) {
      LoggingService.debug('CesiumWebViewController: Clear cache error: $e');
    }
  }
  
  /// Pauses WebView timers (for app lifecycle)
  Future<void> pauseTimers() async {
    if (_isDisposed || _controller == null) return;
    
    try {
      await _controller!.pauseTimers();
      LoggingService.debug('CesiumWebViewController: Timers paused');
    } catch (e) {
      LoggingService.debug('CesiumWebViewController: Pause timers error: $e');
    }
  }
  
  /// Resumes WebView timers (for app lifecycle)
  Future<void> resumeTimers() async {
    if (_isDisposed || _controller == null) return;
    
    try {
      await _controller!.resumeTimers();
      LoggingService.debug('CesiumWebViewController: Timers resumed');
    } catch (e) {
      LoggingService.debug('CesiumWebViewController: Resume timers error: $e');
    }
  }
  
  /// Cleans up Cesium resources via JavaScript
  Future<void> cleanupCesium() async {
    if (_isDisposed || _controller == null) return;
    
    await evaluateJavascript(
      source: '''
        if (typeof cleanupCesium === 'function') {
          cleanupCesium();
        }
        // Stop any running timers
        if (typeof cleanupTimer !== 'undefined') {
          clearInterval(cleanupTimer);
        }
        // Clear viewer reference
        if (window.viewer) {
          window.viewer = null;
        }
      ''',
      timeout: const Duration(milliseconds: 500),
    );
  }
  
  /// Handles memory pressure by reducing Cesium quality
  Future<void> handleMemoryPressure() async {
    if (_isDisposed || _controller == null) return;
    
    LoggingService.warning('CesiumWebViewController: Handling memory pressure');
    
    // Clear WebView cache
    await clearCache();
    
    // Execute aggressive garbage collection in JavaScript
    await evaluateJavascript(source: '''
      if (window.viewer) {
        // Clear all resources
        viewer.scene.primitives.removeAll();
        viewer.entities.removeAll();
        viewer.dataSources.removeAll();
        
        // Reset tile cache completely
        viewer.scene.globe.tileCache.reset();
        
        // Reduce cache size and memory limits drastically
        viewer.scene.globe.tileCacheSize = 5;
        viewer.scene.globe.maximumMemoryUsage = 64;  // Reduce to 64MB
        viewer.scene.globe.maximumScreenSpaceError = 8;  // Lower quality to save memory
        viewer.scene.maximumTextureSize = 512;  // Smaller textures
        
        // Request render to apply new limits
        viewer.scene.requestRender();
        
        // Force JavaScript garbage collection if available
        if (window.gc) {
          window.gc();
        }
        
        cesiumLog.info('Memory pressure: Aggressive cleanup completed');
      }
    ''');
  }
  
  /// Disposes the WebView controller
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    _isDisposed = true;
    _disposeTimer?.cancel();
    
    // Try JavaScript cleanup first
    await cleanupCesium();
    
    // Stop loading
    await stopLoading();
    
    // Clear cache
    await clearCache();
    
    // Clear controller reference
    _controller = null;
    
    LoggingService.debug('CesiumWebViewController: Disposed');
  }
  
  /// Schedules disposal for the next frame
  void scheduleDispose() {
    if (_isDisposed) return;
    
    _disposeTimer?.cancel();
    _disposeTimer = Timer(Duration.zero, () {
      dispose();
    });
  }
}