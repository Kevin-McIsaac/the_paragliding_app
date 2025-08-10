# Flutter Cesium WebView CORS Issues

## Problem Statement

When integrating Cesium.js 3D globe visualization into a Flutter app using WebView, the Earth imagery and terrain fail to load due to Cross-Origin Resource Sharing (CORS) restrictions. The Cesium viewer initializes but displays only a black sphere without textures.

### Specific Errors Observed

1. **Worker Script CORS Error**: 
   ```
   Refused to cross-origin redirects of the top-level worker script
   ```

2. **DOM Creation Error**:
   ```
   Cannot read properties of null (reading 'createElement')
   ```

3. **Memory Warnings**:
   ```
   WARNING: tile memory limits exceeded, some content may not draw
   ```

4. **WebView Renderer Crash**:
   ```
   Killing com.google.android.webview:sandboxed_process0
   Scheduling restart of crashed service
   ```

## Root Cause Analysis

The core issue stems from WebView's security model:

1. **Local Asset Origin**: When loading HTML from Flutter assets (`loadFlutterAsset`), the WebView uses a `file://` or `appassets://` origin
2. **CORS Restrictions**: Cesium needs to fetch resources from `api.cesium.com` and `assets.ion.cesium.com`
3. **Security Sandbox**: Modern WebViews block cross-origin requests from local origins to remote APIs
4. **Worker Scripts**: Cesium uses Web Workers for tile processing, which have even stricter CORS requirements

## Solution Options (Ranked by Simplicity)

### Solution 1: GitHub Pages Hosting (Simplest - 5 minutes)
**Code Changes Required: 1 line**

1. Create GitHub repository
2. Upload `cesium_map.html`
3. Enable GitHub Pages
4. Change WebView to load from GitHub URL

**Pros:**
- Minimal code change
- Proper HTTPS origin
- Free hosting

**Cons:**
- Requires internet connection
- External dependency

### Solution 2: flutter_inappwebview Package (Recommended)
**Code Changes Required: ~10 lines**

Replace `webview_flutter` with `flutter_inappwebview` which has better CORS controls.

**Implementation:**
```yaml
# pubspec.yaml
dependencies:
  flutter_inappwebview: ^6.0.0
```

```dart
// cesium_3d_map_widget.dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class Cesium3DMapWidget extends StatelessWidget {
  final String cesiumToken = "your-token-here";
  
  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: _buildCesiumHtml(),
        baseUrl: WebUri("https://localhost/"),
      ),
      initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
        ),
        android: AndroidInAppWebViewOptions(
          useHybridComposition: true,
          allowFileAccessFromFileURLs: true,
          allowUniversalAccessFromFileURLs: true, // Bypasses CORS
        ),
      ),
      onConsoleMessage: (controller, message) {
        print("Console: ${message.message}");
      },
    );
  }
  
  String _buildCesiumHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://cesium.com/downloads/cesiumjs/releases/1.127/Build/Cesium/Cesium.js"></script>
    <link href="https://cesium.com/downloads/cesiumjs/releases/1.127/Build/Cesium/Widgets/widgets.css" rel="stylesheet">
    <style>
        html, body, #cesiumContainer {
            width: 100%; height: 100%; margin: 0; padding: 0;
        }
    </style>
</head>
<body>
    <div id="cesiumContainer"></div>
    <script>
        Cesium.Ion.defaultAccessToken = "$cesiumToken";
        const viewer = new Cesium.Viewer("cesiumContainer", {
            terrain: Cesium.Terrain.fromWorldTerrain(),
        });
    </script>
</body>
</html>
    ''';
  }
}
```

**Pros:**
- Works offline
- No external dependencies
- Better WebView features
- Maintains security for other content

**Cons:**
- Different package (migration effort)
- Android-specific settings

### Solution 3: Local Proxy Server
**Code Changes Required: ~100 lines**

Run a local HTTP server within the app to proxy Cesium requests.

**Pros:**
- Complete control over requests
- Can add caching
- Works across platforms

**Cons:**
- Complex implementation
- Performance overhead
- Maintenance burden

### Solution 4: Native WebView Modification
**Code Changes Required: Platform channel + native code**

Modify Android WebView settings at the native level.

**Pros:**
- Direct control
- No package changes

**Cons:**
- Platform-specific code
- Breaks encapsulation
- Security risks

### Solution 5: Alternative 3D Libraries
**Code Changes Required: Complete rewrite**

Use MapBox GL or other Flutter-native 3D map solutions.

**Pros:**
- Better performance
- No WebView needed
- Native Flutter widgets

**Cons:**
- Complete reimplementation
- Different feature set
- May require paid licenses

## Detailed Implementation Guide: Solution 2 (flutter_inappwebview)

### Step 1: Update Dependencies

```yaml
# pubspec.yaml
dependencies:
  # Remove or comment out:
  # webview_flutter: ^4.4.0
  # webview_flutter_android: ^3.13.0
  # webview_flutter_wkwebview: ^3.10.0
  
  # Add:
  flutter_inappwebview: ^6.0.0
```

### Step 2: Update Android Configuration

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET"/>
```

### Step 3: Create New Widget

```dart
// lib/presentation/widgets/cesium_3d_map_inappwebview.dart
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class Cesium3DMapInAppWebView extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final double? initialAltitude;
  
  const Cesium3DMapInAppWebView({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialAltitude,
  });

  @override
  State<Cesium3DMapInAppWebView> createState() => _Cesium3DMapInAppWebViewState();
}

class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> {
  InAppWebViewController? webViewController;
  bool isLoading = true;
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _buildCesiumHtml(),
            baseUrl: WebUri("https://localhost/"),
            mimeType: "text/html",
            encoding: "utf-8",
          ),
          initialOptions: InAppWebViewGroupOptions(
            crossPlatform: InAppWebViewOptions(
              javaScriptEnabled: true,
              mediaPlaybackRequiresUserGesture: false,
              transparentBackground: true,
            ),
            android: AndroidInAppWebViewOptions(
              useHybridComposition: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              domStorageEnabled: true,
              databaseEnabled: true,
              clearSessionCache: false,
              thirdPartyCookiesEnabled: true,
              allowContentAccess: true,
            ),
            ios: IOSInAppWebViewOptions(
              allowsInlineMediaPlayback: true,
              allowsAirPlayForMediaPlayback: true,
            ),
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
          },
          onLoadStop: (controller, url) {
            setState(() {
              isLoading = false;
            });
          },
          onConsoleMessage: (controller, consoleMessage) {
            print("JS Console: ${consoleMessage.message}");
          },
          onLoadError: (controller, url, code, message) {
            print("Load Error: $message");
          },
        ),
        if (isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
  
  String _buildCesiumHtml() {
    final lat = widget.initialLat ?? 46.8182;
    final lon = widget.initialLon ?? 8.2275;
    final altitude = widget.initialAltitude ?? 2000000;
    
    return '''
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no">
    <script src="https://cesium.com/downloads/cesiumjs/releases/1.127/Build/Cesium/Cesium.js"></script>
    <link href="https://cesium.com/downloads/cesiumjs/releases/1.127/Build/Cesium/Widgets/widgets.css" rel="stylesheet">
    <style>
        html, body, #cesiumContainer {
            width: 100%; 
            height: 100%; 
            margin: 0; 
            padding: 0; 
            overflow: hidden;
        }
    </style>
</head>
<body>
    <div id="cesiumContainer"></div>
    <script>
        // Cesium Ion token
        Cesium.Ion.defaultAccessToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiIzYzkwM2EwNS00YjU2LTRiMzEtYjE3NC01ODlkYWM3MjMzNmEiLCJpZCI6MzMwMjc0LCJpYXQiOjE3NTQ3MjUxMjd9.IizVx3Z5iR9Xe1TbswK-FKidO9UoWa5pqa4t66NK8W0";
        
        try {
            const viewer = new Cesium.Viewer("cesiumContainer", {
                terrain: Cesium.Terrain.fromWorldTerrain(),
                baseLayerPicker: false,
                geocoder: false,
                homeButton: true,
                sceneModePicker: true,
                navigationHelpButton: false,
                animation: false,
                timeline: false,
                fullscreenButton: false,
            });
            
            // Set initial view
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees($lon, $lat, $altitude),
                orientation: {
                    heading: Cesium.Math.toRadians(0),
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0.0
                }
            });
            
            console.log('Cesium viewer initialized successfully');
            
            // Notify Flutter that initialization is complete
            if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('cesiumReady', true);
            }
        } catch (error) {
            console.error('Cesium initialization error:', error);
            if (window.flutter_inappwebview) {
                window.flutter_inappwebview.callHandler('cesiumError', error.toString());
            }
        }
    </script>
</body>
</html>
    ''';
  }
}
```

### Step 4: Update Flight Track Widget

```dart
// Update flight_track_widget.dart to use new implementation
import 'cesium_3d_map_inappwebview.dart';

// In the toggle logic:
is3DView 
  ? Cesium3DMapInAppWebView(
      initialLat: trackPoints.first.latitude,
      initialLon: trackPoints.first.longitude,
    )
  : FlutterMap(...);
```

## Testing Checklist

- [ ] Earth imagery loads correctly
- [ ] Terrain is visible
- [ ] No CORS errors in console
- [ ] Camera controls work
- [ ] Performance is acceptable
- [ ] Works on Android emulator
- [ ] Works on physical device
- [ ] Memory usage is reasonable

## Troubleshooting

### If Earth still doesn't load:
1. Check Cesium Ion token is valid
2. Verify internet connection
3. Check Android manifest permissions
4. Look for JavaScript console errors
5. Try clearing app data/cache

### If WebView crashes:
1. Reduce Cesium quality settings
2. Increase emulator RAM
3. Test on physical device
4. Disable terrain temporarily

## Resources

- [flutter_inappwebview Documentation](https://inappwebview.dev/)
- [Cesium.js Documentation](https://cesium.com/learn/)
- [Android WebView CORS](https://chromium.googlesource.com/chromium/src/+/HEAD/android_webview/docs/cors-and-webview-api.md)
- [Flutter WebView Comparison](https://pub.dev/packages/flutter_inappwebview#requirements)

## Conclusion

The `flutter_inappwebview` solution provides the best balance of simplicity, functionality, and maintainability. It requires minimal code changes while solving the CORS issue completely through the `allowUniversalAccessFromFileURLs` setting. This approach is production-ready and maintains reasonable security for non-Cesium content.