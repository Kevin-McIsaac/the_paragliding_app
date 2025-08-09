import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CesiumTestWidget extends StatefulWidget {
  const CesiumTestWidget({super.key});

  @override
  State<CesiumTestWidget> createState() => _CesiumTestWidgetState();
}

class _CesiumTestWidgetState extends State<CesiumTestWidget> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            print('CesiumTest: Page started loading');
          },
          onPageFinished: (String url) {
            print('CesiumTest: Page finished loading');
          },
          onWebResourceError: (WebResourceError error) {
            print('CesiumTest Error: ${error.description}');
          },
        ),
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        print('CesiumTest JS: ${message.level.name}: ${message.message}');
      })
      ..loadHtmlString(_buildMinimalCesiumHTML());
  }

  String _buildMinimalCesiumHTML() {
    // Zurich coordinates: 47.3769° N, 8.5417° E
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <script src="https://cesium.com/downloads/cesiumjs/releases/1.111/Build/Cesium/Cesium.js"></script>
    <link href="https://cesium.com/downloads/cesiumjs/releases/1.111/Build/Cesium/Widgets/widgets.css" rel="stylesheet">
    <style>
        html, body, #cesiumContainer {
            width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden;
        }
        #status {
            position: absolute;
            top: 10px;
            left: 10px;
            background: rgba(42, 42, 42, 0.8);
            color: white;
            padding: 10px;
            border-radius: 5px;
            font-family: monospace;
            z-index: 1000;
        }
    </style>
</head>
<body>
    <div id="cesiumContainer"></div>
    <div id="status">Initializing Cesium...</div>
    
    <script>
        // Simple status updater
        function updateStatus(msg) {
            console.log('Status: ' + msg);
            document.getElementById('status').innerHTML = msg;
        }
        
        try {
            updateStatus('Creating viewer...');
            
            // CRITICAL: Disable WebWorkers for Android compatibility
            window.CESIUM_BASE_URL = undefined;
            Cesium.TaskProcessor.prototype.scheduleTask = function(parameters, transferableObjects) {
                // Run tasks synchronously instead of in workers
                const processor = this._processor;
                if (processor && processor.func) {
                    return Promise.resolve(processor.func(parameters));
                }
                return Promise.reject(new Error('No processor available'));
            };
            
            // Skip Ion completely
            Cesium.Ion.defaultAccessToken = undefined;
            
            // Create viewer with OpenStreetMap imagery (no auth needed)
            const viewer = new Cesium.Viewer('cesiumContainer', {
                // Disable all UI for simplicity
                animation: false,
                baseLayerPicker: false,
                fullscreenButton: false,
                geocoder: false,
                homeButton: false,
                infoBox: false,
                sceneModePicker: false,
                selectionIndicator: false,
                timeline: false,
                navigationHelpButton: false,
                vrButton: false,
                
                // Use simple ellipsoid terrain (no external data)
                terrainProvider: new Cesium.EllipsoidTerrainProvider(),
                
                // Use OpenStreetMap tiles (no authentication required)
                imageryProvider: new Cesium.UrlTemplateImageryProvider({
                    url: 'https://a.tile.openstreetmap.org/{z}/{x}/{y}.png',
                    maximumLevel: 18,
                    credit: 'OpenStreetMap'
                })
            });
            
            updateStatus('Viewer created with terrain. Setting camera...');
            
            // Set camera to 10km above Zurich
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(
                    8.5417,  // Longitude (Zurich)
                    47.3769, // Latitude (Zurich)
                    10000    // Height: 10km
                ),
                orientation: {
                    heading: Cesium.Math.toRadians(0),     // North
                    pitch: Cesium.Math.toRadians(-45),     // Look down at 45 degrees
                    roll: 0.0
                }
            });
            
            updateStatus('Camera positioned 10km above Zurich');
            
            // Add a simple red marker at Zurich
            viewer.entities.add({
                name: 'Zurich',
                position: Cesium.Cartesian3.fromDegrees(8.5417, 47.3769, 100),
                point: {
                    pixelSize: 10,
                    color: Cesium.Color.RED,
                    outlineColor: Cesium.Color.WHITE,
                    outlineWidth: 2
                }
            });
            
            updateStatus('Ready! Zurich marked in red.');
            
            // Deep diagnostic check after 3 seconds
            setTimeout(() => {
                try {
                    const globe = viewer.scene.globe;
                    const terrainProvider = viewer.terrainProvider;
                    const imageryLayers = viewer.imageryLayers;
                    
                    // Check if we're getting Ion errors
                    const ionError = Cesium.Ion.defaultAccessToken ? 'Token present' : 'No token';
                    
                    // Check terrain provider details
                    let terrainInfo = 'none';
                    if (terrainProvider) {
                        terrainInfo = terrainProvider.constructor.name + 
                                     ', ready=' + terrainProvider.ready + 
                                     ', error=' + (terrainProvider.errorEvent ? 'yes' : 'no');
                    }
                    
                    // Check imagery provider details
                    let imageryInfo = 'none';
                    if (imageryLayers && imageryLayers.length > 0) {
                        const layer = imageryLayers.get(0);
                        if (layer && layer.imageryProvider) {
                            const provider = layer.imageryProvider;
                            imageryInfo = provider.constructor.name + 
                                         ', ready=' + provider.ready;
                        }
                    }
                    
                    // Check WebGL context
                    const webglInfo = viewer.scene.context ? 'WebGL OK' : 'No WebGL';
                    
                    // Check if globe is actually showing
                    const globeShow = globe ? globe.show : 'no globe';
                    
                    const diagnostics = 'Ion: ' + ionError + ', Terrain: ' + terrainInfo + ', Globe: ' + globeShow;
                    updateStatus(diagnostics);
                    
                    console.log('Deep diagnostics:', {
                        ion: ionError,
                        terrain: terrainInfo,
                        imagery: imageryInfo,
                        webgl: webglInfo,
                        globeShow: globeShow,
                        backgroundColor: viewer.scene.backgroundColor.toString()
                    });
                    
                    // Try to force a render
                    viewer.scene.requestRender();
                    
                } catch (e) {
                    updateStatus('Diagnostic error: ' + e.message);
                    console.error('Diagnostic error:', e);
                }
            }, 3000);
            
        } catch (error) {
            const errorMsg = 'Error: ' + error.message;
            updateStatus(errorMsg);
            console.error('Cesium initialization error:', error);
        }
    </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}