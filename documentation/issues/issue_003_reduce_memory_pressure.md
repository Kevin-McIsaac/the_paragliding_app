# Issue #003: Reduce Memory Pressure

**Priority:** High  
**Component:** Cesium 3D Map / WebView  
**Type:** Performance / Memory Optimization  

## Problem Description

The Android low memory killer is being triggered frequently, indicating high memory usage. The app is consuming significant memory, particularly when the 3D Cesium view is active.

## Evidence from Logs

```
15:10:28.603 I lowmemorykiller: Reclaimed 79344kB, cache(318020kB) and free(121924kB)-reserved(49788kB) below min(322560kB)
15:10:28.618 I lowmemorykiller: Skipping kill; 79344 kB freed elsewhere.
15:10:48.734 I _flight_log_app: NativeAlloc concurrent copying GC freed 21304(1001KB), 49% free, 4531KB/9061KB
```

Multiple lowmemorykiller activations show the system is under memory pressure.

## Root Cause

1. Cesium loads high-resolution terrain and imagery data
2. WebView maintains large tile cache
3. No memory limits configured for WebView
4. Terrain and imagery providers using maximum quality
5. Multiple imagery layers loaded simultaneously

## Proposed Solution

### 1. Configure WebView Memory Limits

```dart
// In cesium_3d_map_inappwebview.dart
InAppWebViewSettings(
  // ... existing settings ...
  
  // Android-specific memory settings
  cacheMode: CacheMode.LOAD_NO_CACHE,  // Don't cache in WebView
  databaseEnabled: false,  // Disable database storage
  domStorageEnabled: false,  // Disable DOM storage
  
  // Limit WebView process memory (Android only)
  rendererPriorityPolicy: RendererPriorityPolicy(
    rendererPriority: RendererPriority.RENDERER_PRIORITY_WAIVED,
    waivedWhenNotVisible: true,
  ),
)
```

### 2. Optimize Cesium Memory Usage

```javascript
const viewer = new Cesium.Viewer("cesiumContainer", {
    // Reduce terrain quality
    terrain: Cesium.Terrain.fromWorldTerrain({
        requestWaterMask: false,
        requestVertexNormals: false,
        // Use lower resolution terrain
        terrainProvider: new Cesium.CesiumTerrainProvider({
            url: Cesium.IonResource.fromAssetId(1),
            requestVertexNormals: false,
            requestWaterMask: false,
            requestMetadata: false
        })
    }),
    
    // Limit scene rendering
    contextOptions: {
        webgl: {
            powerPreference: 'low-power',  // Use low-power GPU
            antialias: false,  // Disable antialiasing
            preserveDrawingBuffer: false,
            failIfMajorPerformanceCaveat: true
        }
    }
});

// Configure memory limits
viewer.scene.globe.tileCacheSize = 20;  // Reduce from default 100
viewer.scene.globe.preloadSiblings = false;  // Don't preload adjacent tiles
viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles

// Limit imagery quality
viewer.scene.globe.maximumScreenSpaceError = 4;  // Higher = lower quality but better performance
viewer.scene.globe.tileCacheSize = 20;

// Set maximum texture size
viewer.scene.maximumTextureSize = 2048;  // Limit texture resolution

// Disable terrain exaggeration
viewer.scene.globe.terrainExaggeration = 1.0;
viewer.scene.globe.terrainExaggerationRelativeHeight = 0.0;
```

### 3. Implement Aggressive Cleanup

```javascript
// Periodically clean up unused resources
let cleanupTimer = setInterval(() => {
    if (viewer && viewer.scene) {
        // Force garbage collection of unused tiles
        viewer.scene.globe.tileCache.trim();
        
        // Clear expired imagery tiles
        viewer.imageryLayers.pickImageryLayerFeatures.cache = {};
        
        // Compact tile cache
        if (viewer.scene.globe.tileCache.count > 20) {
            viewer.scene.globe.tileCache.reset();
        }
    }
}, 30000);  // Every 30 seconds

// Clean up on page unload
window.addEventListener('beforeunload', () => {
    clearInterval(cleanupTimer);
    if (viewer) {
        viewer.scene.primitives.removeAll();
        viewer.destroy();
    }
});
```

### 4. Add Memory Monitoring

```dart
// Add memory monitoring to detect issues
Timer.periodic(Duration(seconds: 10), (timer) {
  if (_isDisposed) {
    timer.cancel();
    return;
  }
  
  // Check memory usage via JavaScript
  webViewController?.evaluateJavascript(source: '''
    if (window.performance && window.performance.memory) {
      const memory = window.performance.memory;
      const usage = {
        used: Math.round(memory.usedJSHeapSize / 1048576),
        total: Math.round(memory.totalJSHeapSize / 1048576),
        limit: Math.round(memory.jsHeapSizeLimit / 1048576)
      };
      
      if (usage.used > usage.total * 0.8) {
        // High memory usage - trigger cleanup
        if (window.viewer) {
          viewer.scene.globe.tileCache.trim();
        }
      }
      
      console.log('Memory: ' + usage.used + 'MB / ' + usage.total + 'MB');
    }
  ''');
});
```

## Implementation Location

Files:
- `/home/kmcisaac/Projects/free_flight_log/free_flight_log_app/lib/presentation/widgets/cesium_3d_map_inappwebview.dart`
- Cesium HTML template in the same file

## Testing Requirements

1. Monitor memory usage with Android Studio Profiler
2. Test on devices with 2GB, 3GB, and 4GB RAM
3. Navigate to/from 3D view repeatedly
4. Leave 3D view open for extended periods
5. Test with flight tracks of varying complexity

## Success Criteria

- [ ] Memory usage stays below 200MB for WebView process
- [ ] No lowmemorykiller activations during normal use
- [ ] Smooth performance on 2GB RAM devices
- [ ] No out-of-memory crashes
- [ ] GC pauses reduced to < 50ms

## Related Issues

- Issue #001: Optimize Cesium Tile Loading
- Issue #002: Fix Resource Leaks