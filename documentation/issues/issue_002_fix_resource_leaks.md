# Issue #002: Fix WebView Resource Leaks

**Priority:** High  
**Component:** InAppWebView Integration  
**Type:** Memory Leak / Resource Management  

## Problem Description

Multiple Android system warnings indicate resources are not being properly released, particularly WebView-related resources and HardwareBuffer instances.

## Evidence from Logs

```
15:09:53.195 W System  : A resource failed to call release.
15:09:53.195 W System  : A resource failed to call HardwareBuffer.close.
15:12:34.773 W System  : A resource failed to call release.
15:12:34.773 W System  : A resource failed to call HardwareBuffer.close.
15:13:00.010 W System  : A resource failed to call SQLiteConnection.close.
```

Multiple occurrences throughout the session indicate systematic resource management issues.

## Root Cause

1. InAppWebViewController not properly disposed
2. WebView native resources not released on widget disposal
3. Missing cleanup of JavaScript channels
4. Potential circular references between Dart and JavaScript

## Proposed Solution

### 1. Properly Dispose WebView Controller

```dart
class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> {
  InAppWebViewController? webViewController;
  bool isLoading = true;
  bool _isDisposed = false;
  
  @override
  void dispose() {
    _isDisposed = true;
    _disposeWebView();
    super.dispose();
  }
  
  Future<void> _disposeWebView() async {
    if (webViewController != null) {
      try {
        // Stop any ongoing JavaScript execution
        await webViewController!.stopLoading();
        
        // Clear cache to free memory
        await webViewController!.clearCache();
        
        // Remove JavaScript handlers
        await webViewController!.removeAllUserScripts();
        
        // Explicitly dispose the controller
        webViewController!.dispose();
        
        // Clear reference
        webViewController = null;
      } catch (e) {
        LoggingService.error('Cesium3D Disposal', 'Error disposing WebView: $e');
      }
    }
  }
}
```

### 2. Add Lifecycle Management

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  super.didChangeAppLifecycleState(state);
  
  switch (state) {
    case AppLifecycleState.paused:
      // Pause WebView when app goes to background
      webViewController?.pauseTimers();
      break;
    case AppLifecycleState.resumed:
      // Resume WebView when app comes to foreground
      if (!_isDisposed) {
        webViewController?.resumeTimers();
      }
      break;
    case AppLifecycleState.detached:
      // Clean up resources
      _disposeWebView();
      break;
    default:
      break;
  }
}
```

### 3. Implement Memory Pressure Handling

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

@override
void didHaveMemoryPressure() {
  super.didHaveMemoryPressure();
  // Clear WebView cache on memory pressure
  webViewController?.clearCache();
  
  // Force garbage collection in JavaScript
  webViewController?.evaluateJavascript(source: '''
    if (window.viewer) {
      viewer.scene.primitives.removeAll();
      viewer.scene.globe.terrainProvider = undefined;
    }
  ''');
}
```

### 4. Add JavaScript Cleanup

```javascript
// In the HTML template, add cleanup function
window.addEventListener('beforeunload', function() {
    if (window.viewer) {
        viewer.destroy();
        window.viewer = null;
    }
});

// Add method to be called from Flutter
function cleanupCesium() {
    if (window.viewer) {
        viewer.scene.primitives.removeAll();
        viewer.entities.removeAll();
        viewer.dataSources.removeAll();
        viewer.imageryLayers.removeAll();
        viewer.destroy();
        window.viewer = null;
    }
}
```

## Implementation Location

File: `/home/kmcisaac/Projects/free_flight_log/free_flight_log_app/lib/presentation/widgets/cesium_3d_map_inappwebview.dart`

## Testing Requirements

1. Monitor logcat for "resource failed to call" warnings
2. Use Android Studio Memory Profiler to track leaks
3. Test rapid navigation to/from 3D view
4. Test app backgrounding and foregrounding
5. Test on low-memory devices

## Success Criteria

- [ ] No "resource failed to call" warnings in logs
- [ ] Memory properly released when leaving 3D view
- [ ] No memory growth over time with repeated navigation
- [ ] WebView resources cleaned up on app termination
- [ ] No crashes due to memory exhaustion

## Related Issues

- Issue #003: Reduce Memory Pressure
- Issue #006: Surface Sync Errors