# Issue #004: Clean Console Logging

**Priority:** Medium  
**Component:** Cesium 3D Map Widget  
**Type:** Code Quality / Performance  

## Problem Description

Excessive console logging is cluttering the debug output and potentially impacting performance. The tile loading progress is logged continuously, making it difficult to identify actual issues.

## Evidence from Logs

```
15:12:47.555 Cesium3D JS [LOG]: Loading tiles: 12 remaining
15:12:47.605 Cesium3D JS [LOG]: Loading tiles: 10 remaining
15:12:47.720 Cesium3D JS [LOG]: Loading tiles: 8 remaining
15:12:47.746 Cesium3D JS [LOG]: Loading tiles: 3 remaining
15:12:47.925 Cesium3D JS [LOG]: Loading tiles: 1 remaining
15:12:48.117 Cesium3D JS [LOG]: Loading tiles: 3 remaining
```

This pattern repeats continuously, generating hundreds of log entries per minute.

## Root Cause

1. Tile loading event listener logs every change
2. No distinction between development and production logging
3. Debug information exposed in production builds
4. No log level filtering

## Proposed Solution

### 1. Implement Conditional Logging

```javascript
// Add debug flag based on build mode
const DEBUG_MODE = false;  // Set via Flutter build configuration

// Create logging wrapper
const cesiumLog = {
    debug: (message) => {
        if (DEBUG_MODE) {
            console.log('[Cesium Debug] ' + message);
        }
    },
    info: (message) => {
        console.log('[Cesium] ' + message);
    },
    error: (message) => {
        console.error('[Cesium Error] ' + message);
    }
};
```

### 2. Refactor Tile Loading Monitoring

```javascript
// Only log significant events
let lastTileCount = -1;
let loadingStartTime = Date.now();
let hasLoggedComplete = false;

viewer.scene.globe.tileLoadProgressEvent.addEventListener(function(queuedTileCount) {
    // Only log initial load completion
    if (queuedTileCount === 0 && !hasLoggedComplete) {
        const loadTime = ((Date.now() - loadingStartTime) / 1000).toFixed(2);
        cesiumLog.info(`Initial tile load complete in \${loadTime}s`);
        hasLoggedComplete = true;
        document.getElementById('loadingOverlay').style.display = 'none';
    }
    
    // Only log significant changes during development
    if (DEBUG_MODE) {
        const change = Math.abs(lastTileCount - queuedTileCount);
        if (change > 10 || (queuedTileCount === 0 && lastTileCount > 0)) {
            cesiumLog.debug(`Tiles queued: \${queuedTileCount}`);
            lastTileCount = queuedTileCount;
        }
    }
});
```

### 3. Add Build Configuration

```dart
// In cesium_3d_map_inappwebview.dart
String _buildCesiumHtml() {
  // Determine if in debug mode
  final bool isDebugMode = !kReleaseMode;
  
  return '''
    <script>
        const DEBUG_MODE = ${isDebugMode ? 'true' : 'false'};
        
        // Rest of the HTML...
    </script>
  ''';
}
```

### 4. Implement Log Level Control

```dart
// Add log level configuration
enum CesiumLogLevel { none, error, warning, info, debug }

class Cesium3DMapInAppWebView extends StatefulWidget {
  final CesiumLogLevel logLevel;
  
  const Cesium3DMapInAppWebView({
    super.key,
    this.logLevel = kDebugMode ? CesiumLogLevel.info : CesiumLogLevel.error,
    // ... other parameters
  });
}

// In the HTML template
<script>
    const LOG_LEVEL = '${widget.logLevel.name}';
    
    const shouldLog = (level) => {
        const levels = ['none', 'error', 'warning', 'info', 'debug'];
        const currentLevel = levels.indexOf(LOG_LEVEL);
        const messageLevel = levels.indexOf(level);
        return messageLevel <= currentLevel && messageLevel > 0;
    };
    
    // Override console methods
    const originalLog = console.log;
    console.log = function(...args) {
        if (shouldLog('info')) {
            originalLog.apply(console, args);
        }
    };
</script>
```

### 5. Clean Up Existing Logs

Remove or conditionalize these verbose logs:
- Tile loading progress (unless significant change)
- Imagery layer added notifications
- Camera position logs
- Terrain provider change events

Replace with meaningful milestone logs:
- Initial load complete
- Errors and warnings only
- Significant user interactions

## Implementation Location

File: `/home/kmcisaac/Projects/free_flight_log/free_flight_log_app/lib/presentation/widgets/cesium_3d_map_inappwebview.dart`

Update the HTML template and add Flutter build mode detection.

## Testing Requirements

1. Verify minimal logging in release builds
2. Ensure error messages still appear
3. Test debug mode shows appropriate detail
4. Monitor console output volume
5. Check performance impact of reduced logging

## Success Criteria

- [ ] Console output reduced by 90% in production
- [ ] Only errors shown in release builds
- [ ] Debug builds show configurable detail level
- [ ] Critical errors always visible
- [ ] Performance improvement measurable

## Related Issues

- Issue #001: Optimize Cesium Tile Loading
- Issue #005: Handle Connection Errors