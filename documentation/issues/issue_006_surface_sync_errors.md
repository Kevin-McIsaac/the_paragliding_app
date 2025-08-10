# Issue #006: Surface Sync Errors

**Priority:** Medium  
**Component:** Android WebView / Surface Rendering  
**Type:** Rendering Issue  

## Problem Description

Android SurfaceSyncer is reporting failures to find sync IDs, potentially causing rendering glitches or visual artifacts in the WebView.

## Evidence from Logs

```
15:10:05.362 E SurfaceSyncer: Failed to find sync for id=0
15:10:06.224 E SurfaceSyncer: Failed to find sync for id=0
15:11:21.393 E SurfaceSyncer: Failed to find sync for id=0
15:11:23.997 E SurfaceSyncer: Failed to find sync for id=0
15:11:23.997 E SurfaceSyncer: Failed to find sync for id=1
15:11:28.607 E SurfaceSyncer: Failed to find sync for id=0
15:11:28.607 E SurfaceSyncer: Failed to find sync for id=1
15:11:28.607 E SurfaceSyncer: Failed to find sync for id=2
```

The errors increase in ID numbers, suggesting accumulation of unsynced surfaces.

## Root Cause

1. WebView surface not properly synchronized with Flutter's rendering
2. Hybrid composition mode may have synchronization issues
3. Rapid navigation or lifecycle changes causing surface orphaning
4. Platform view integration timing issues

## Proposed Solution

### 1. Improve Surface Lifecycle Management

```dart
class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> 
    with AutomaticKeepAliveClientMixin {
  
  // Keep widget alive to prevent surface recreation
  @override
  bool get wantKeepAlive => true;
  
  // Track visibility to manage surface
  bool _isVisible = true;
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return Visibility(
      visible: _isVisible,
      maintainState: true,  // Keep state when hidden
      maintainAnimation: true,
      maintainSize: true,
      child: _buildWebView(),
    );
  }
}
```

### 2. Configure Hybrid Composition Settings

```dart
InAppWebViewSettings(
  // Existing settings...
  
  // Android-specific surface settings
  useHybridComposition: true,  // Currently true, but may need adjustment
  
  // Alternative: Try without hybrid composition
  // useHybridComposition: false,  // Uses Virtual Display instead
  
  // Ensure proper surface handling
  hardwareAcceleration: true,
  supportMultipleWindows: false,
  useWideViewPort: false,
  
  // Render priority
  rendererPriorityPolicy: RendererPriorityPolicy(
    rendererPriority: RendererPriority.RENDERER_PRIORITY_IMPORTANT,
    waivedWhenNotVisible: false,  // Keep surface active
  ),
)
```

### 3. Implement Deferred WebView Creation

```dart
class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> {
  bool _isWebViewReady = false;
  
  @override
  void initState() {
    super.initState();
    // Defer WebView creation to avoid surface sync issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isWebViewReady = true;
        });
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isWebViewReady) {
      return Center(child: CircularProgressIndicator());
    }
    
    return InAppWebView(
      // WebView configuration...
    );
  }
}
```

### 4. Add Surface Error Recovery

```dart
// Track and recover from surface errors
int _surfaceErrorCount = 0;
Timer? _surfaceRecoveryTimer;

void _handleSurfaceError() {
  _surfaceErrorCount++;
  
  if (_surfaceErrorCount > 3) {
    // Too many errors - recreate WebView
    _surfaceRecoveryTimer?.cancel();
    _surfaceRecoveryTimer = Timer(Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isWebViewReady = false;
        });
        
        // Recreate after delay
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isWebViewReady = true;
              _surfaceErrorCount = 0;
            });
          }
        });
      }
    });
  }
}
```

### 5. Platform-Specific Workaround

```dart
// For Android API level differences
import 'dart:io';

InAppWebViewSettings _getOptimizedSettings() {
  if (Platform.isAndroid) {
    // Check Android version and adjust
    return InAppWebViewSettings(
      // Use Virtual Display for older Android versions
      useHybridComposition: _shouldUseHybridComposition(),
      // Other settings...
    );
  }
  return InAppWebViewSettings(/* iOS settings */);
}

bool _shouldUseHybridComposition() {
  // Hybrid composition is more stable on Android 10+
  // Virtual Display may work better on older versions
  // This would need native platform channel to check API level
  return true; // Default to hybrid composition
}
```

### 6. Add Diagnostic Logging

```dart
@override
void initState() {
  super.initState();
  
  // Monitor surface lifecycle
  if (kDebugMode) {
    WidgetsBinding.instance.addObserver(LifecycleObserver(
      onResume: () => LoggingService.debug('Surface: App resumed'),
      onPause: () => LoggingService.debug('Surface: App paused'),
    ));
  }
}

// In WebView callbacks
onWebViewCreated: (controller) {
  LoggingService.debug('Surface: WebView created');
},

onLoadStop: (controller, url) {
  LoggingService.debug('Surface: Load complete');
},
```

## Implementation Location

File: `/home/kmcisaac/Projects/free_flight_log/free_flight_log_app/lib/presentation/widgets/cesium_3d_map_inappwebview.dart`

## Testing Requirements

1. Navigate to/from 3D view rapidly (10+ times)
2. Background and restore app while 3D view is active
3. Rotate device while 3D view is displayed
4. Test on different Android versions (API 21-34)
5. Monitor logcat for SurfaceSyncer errors

## Success Criteria

- [ ] No SurfaceSyncer errors in normal use
- [ ] Smooth transitions to/from 3D view
- [ ] No visual glitches or black screens
- [ ] WebView renders immediately without flicker
- [ ] Surface properly cleaned up on disposal

## Related Issues

- Issue #002: Fix Resource Leaks
- Issue #003: Reduce Memory Pressure

## Notes

This issue may be related to the InAppWebView package implementation and might require:
- Updating to latest InAppWebView version
- Filing issue with InAppWebView repository
- Considering alternative WebView packages if unresolvable