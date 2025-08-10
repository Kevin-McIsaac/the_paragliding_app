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
            const viewer = new Cesium.Viewer("cesiumContainer", {
                terrain: Cesium.Terrain.fromWorldTerrain(),
                baseLayerPicker: true,
                geocoder: false,
                homeButton: true,
                sceneModePicker: true,
                navigationHelpButton: true,
                animation: true,
                timeline: true,
                fullscreenButton: false,
                vrButton: false,
                infoBox: false,
                selectionIndicator: false,
                shadows: false,
                shouldAnimate: false,
            });
            
            console.log('Cesium viewer created, setting initial view...');
            
            // Hide loading overlay once viewer is ready
            viewer.scene.globe.tileLoadProgressEvent.addEventListener(function(queuedTileCount) {
                if (queuedTileCount === 0) {
                    document.getElementById('loadingOverlay').style.display = 'none';
                }
            });
            
            // Set initial camera view
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees($lon, $lat, $altitude),
                orientation: {
                    heading: Cesium.Math.toRadians(0),
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0.0
                }
            });
            
            console.log('Cesium viewer initialized successfully');
            console.log('Camera position set to: lat=$lat, lon=$lon, altitude=$altitude');
            
            // Add some debug info
            viewer.scene.globe.enableLighting = false;
            viewer.scene.globe.showGroundAtmosphere = true;
            viewer.scene.globe.baseColor = Cesium.Color.BLUE.withAlpha(0.5);
            
            // Log tile loading events
            viewer.scene.globe.tileLoadProgressEvent.addEventListener(function(queuedTileCount) {
                if (queuedTileCount > 0) {
                    console.log('Loading tiles: ' + queuedTileCount + ' remaining');
                }
            });
            
            // Check if imagery layers are loading
            viewer.scene.imageryLayers.layerAdded.addEventListener(function(layer, index) {
                console.log('Imagery layer added at index ' + index);
            });
            
            // Check for any errors
            viewer.scene.globe.terrainProviderChanged.addEventListener(function() {
                console.log('Terrain provider changed');
            });
            
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