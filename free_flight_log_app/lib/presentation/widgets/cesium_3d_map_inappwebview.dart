import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../services/logging_service.dart';

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
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: false,
            transparentBackground: true,
            // Android-specific settings that bypass CORS
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,  // This is the key setting for CORS bypass
            domStorageEnabled: true,
            databaseEnabled: true,
            clearSessionCache: false,
            thirdPartyCookiesEnabled: true,
            allowContentAccess: true,
            useHybridComposition: true,
            // iOS-specific settings
            allowsInlineMediaPlayback: true,
            allowsAirPlayForMediaPlayback: true,
          ),
          onWebViewCreated: (controller) {
            webViewController = controller;
            LoggingService.debug('Cesium3D InAppWebView: WebView created');
          },
          onLoadStop: (controller, url) async {
            LoggingService.debug('Cesium3D InAppWebView: Page loaded');
            setState(() {
              isLoading = false;
            });
          },
          onConsoleMessage: (controller, consoleMessage) {
            final level = consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ? 'ERROR' :
                         consoleMessage.messageLevel == ConsoleMessageLevel.WARNING ? 'WARNING' :
                         consoleMessage.messageLevel == ConsoleMessageLevel.LOG ? 'LOG' : 'DEBUG';
            LoggingService.debug('Cesium3D JS [$level]: ${consoleMessage.message}');
          },
          onLoadError: (controller, url, code, message) {
            LoggingService.error('Cesium3D InAppWebView', 'Load error: $message (code: $code)');
          },
          onReceivedError: (controller, request, error) {
            LoggingService.error('Cesium3D InAppWebView', 'Received error: ${error.description}');
          },
          onReceivedHttpError: (controller, request, response) {
            LoggingService.error('Cesium3D InAppWebView', 'HTTP error: ${response.statusCode} - ${response.reasonPhrase}');
          },
          onJsAlert: (controller, jsAlertRequest) async {
            LoggingService.debug('Cesium3D JS Alert: ${jsAlertRequest.message}');
            return JsAlertResponse(handledByClient: true);
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
    // Use provided coordinates or default to Switzerland (typical paragliding area)
    final lat = widget.initialLat ?? 46.8182;
    final lon = widget.initialLon ?? 8.2275;
    final altitude = widget.initialAltitude ?? 2000000; // 2000km altitude for good view
    
    return '''
<!DOCTYPE html>
<html lang="en">
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
            font-family: sans-serif;
        }
        #loadingOverlay {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: white;
            font-size: 16px;
            text-align: center;
            z-index: 100;
        }
    </style>
</head>
<body>
    <div id="cesiumContainer"></div>
    <div id="loadingOverlay">Loading Cesium Globe...</div>
    
    <script>
        // Cesium Ion token
        Cesium.Ion.defaultAccessToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiIzYzkwM2EwNS00YjU2LTRiMzEtYjE3NC01ODlkYWM3MjMzNmEiLCJpZCI6MzMwMjc0LCJpYXQiOjE3NTQ3MjUxMjd9.IizVx3Z5iR9Xe1TbswK-FKidO9UoWa5pqa4t66NK8W0";
        
        console.log('Starting Cesium initialization...');
        
        try {
            // Optimized Cesium viewer settings for performance
            const viewer = new Cesium.Viewer("cesiumContainer", {
                terrain: Cesium.Terrain.fromWorldTerrain({
                    requestWaterMask: false,  // Disable water effects
                    requestVertexNormals: false  // Disable lighting calculations
                }),
                scene3DOnly: true,  // Disable 2D/Columbus view modes for performance
                requestRenderMode: true,  // Only render on demand
                maximumRenderTimeChange: Infinity,  // Reduce re-renders
                targetFrameRate: 30,  // Lower frame rate for mobile
                resolutionScale: 0.75,  // Reduce resolution for better performance
                
                // Disable unused widgets to reduce overhead
                baseLayerPicker: false,
                geocoder: false,
                homeButton: true,
                sceneModePicker: false,
                navigationHelpButton: false,
                animation: false,
                timeline: false,
                fullscreenButton: false,
                vrButton: false,
                infoBox: false,
                selectionIndicator: false,
                shadows: false,
                shouldAnimate: false,
            });
            
            console.log('Cesium viewer created, configuring performance settings...');
            
            // Configure scene for optimal performance
            viewer.scene.globe.enableLighting = false;
            viewer.scene.globe.showGroundAtmosphere = false;  // Disable atmosphere for performance
            viewer.scene.fog.enabled = false;  // Disable fog
            viewer.scene.globe.depthTestAgainstTerrain = false;  // Faster rendering
            viewer.scene.screenSpaceCameraController.enableCollisionDetection = false;
            
            // Limit tile cache size to reduce memory usage
            viewer.scene.globe.tileCacheSize = 50;  // Reduced from default 100
            viewer.scene.globe.preloadSiblings = false;  // Don't preload adjacent tiles
            viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles
            
            // Set maximum screen space error (higher = lower quality but better performance)
            viewer.scene.globe.maximumScreenSpaceError = 4;  // Default is 2
            
            // Configure imagery provider for better performance
            const imageryProvider = viewer.imageryLayers.get(0);
            if (imageryProvider) {
                imageryProvider.brightness = 1.0;
                imageryProvider.contrast = 1.0;
                imageryProvider.saturation = 1.0;
            }
            
            // Set initial camera view
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees($lon, $lat, $altitude),
                orientation: {
                    heading: Cesium.Math.toRadians(0),
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0.0
                }
            });
            
            // Track initial load completion and stop logging after that
            let initialLoadComplete = false;
            const tileLoadHandler = function(queuedTileCount) {
                if (queuedTileCount === 0 && !initialLoadComplete) {
                    initialLoadComplete = true;
                    console.log('Initial tile load complete');
                    document.getElementById('loadingOverlay').style.display = 'none';
                    
                    // Remove the listener after initial load to stop logging
                    viewer.scene.globe.tileLoadProgressEvent.removeEventListener(tileLoadHandler);
                } else if (!initialLoadComplete && queuedTileCount > 0) {
                    // Only log during initial load, and only significant changes
                    if (queuedTileCount % 5 === 0) {
                        console.log('Loading tiles: ' + queuedTileCount + ' remaining');
                    }
                }
            };
            viewer.scene.globe.tileLoadProgressEvent.addEventListener(tileLoadHandler);
            
            console.log('Cesium viewer initialized successfully');
            console.log('Camera position set to: lat=$lat, lon=$lon, altitude=$altitude');
            
        } catch (error) {
            console.error('Cesium initialization error:', error);
            console.error('Error stack:', error.stack);
            document.getElementById('loadingOverlay').innerHTML = 'Error loading Cesium: ' + error.message;
        }
    </script>
</body>
</html>
    ''';
  }
  
  @override
  void dispose() {
    webViewController?.dispose();
    super.dispose();
  }
}