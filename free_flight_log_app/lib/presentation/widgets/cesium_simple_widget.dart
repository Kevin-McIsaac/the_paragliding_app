import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CesiumSimpleWidget extends StatefulWidget {
  const CesiumSimpleWidget({super.key});

  @override
  State<CesiumSimpleWidget> createState() => _CesiumSimpleWidgetState();
}

class _CesiumSimpleWidgetState extends State<CesiumSimpleWidget> {
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
            print('CesiumSimple: Page started loading');
          },
          onPageFinished: (String url) {
            print('CesiumSimple: Page finished loading');
          },
          onWebResourceError: (WebResourceError error) {
            print('CesiumSimple Error: ${error.description}');
          },
        ),
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        print('CesiumSimple JS: ${message.level.name}: ${message.message}');
      })
      ..loadHtmlString(_buildWorkingCesiumHTML());
  }

  String _buildWorkingCesiumHTML() {
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
            background: rgba(42, 42, 42, 0.9);
            color: white;
            padding: 10px;
            border-radius: 5px;
            font-family: monospace;
            font-size: 12px;
            z-index: 1000;
        }
    </style>
</head>
<body>
    <div id="cesiumContainer"></div>
    <div id="status">Initializing...</div>
    
    <script>
        function updateStatus(msg) {
            console.log('Status: ' + msg);
            document.getElementById('status').innerHTML = msg;
        }
        
        try {
            updateStatus('Starting Cesium...');
            
            // Disable Ion completely - we don't need it
            Cesium.Ion.defaultAccessToken = undefined;
            
            // Create the simplest possible viewer
            const viewer = new Cesium.Viewer('cesiumContainer', {
                // Hide all UI controls
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
                
                // No terrain - just a smooth sphere
                terrainProvider: new Cesium.EllipsoidTerrainProvider(),
                
                // No imagery provider initially
                imageryProvider: false,
                
                // Disable shadows and other effects
                shadows: false,
                terrainShadows: Cesium.ShadowMode.DISABLED,
                
                // Disable request render mode
                requestRenderMode: false,
                maximumRenderTimeChange: Infinity
            });
            
            updateStatus('Viewer created');
            
            // Set a nice blue color for the globe (ocean)
            viewer.scene.globe.baseColor = new Cesium.Color(0.1, 0.3, 0.6, 1.0);
            viewer.scene.globe.enableLighting = false;
            
            // Set sky to light blue instead of black space
            viewer.scene.skyBox.show = false;
            viewer.scene.backgroundColor = new Cesium.Color(0.5, 0.7, 0.9, 1.0);
            
            // Add a simple grid overlay to show the globe is working
            const gridMaterial = Cesium.Material.fromType('Grid', {
                cellAlpha: 0.1,
                lineCount: new Cesium.Cartesian2(30, 30),
                lineThickness: new Cesium.Cartesian2(2.0, 2.0),
                lineOffset: new Cesium.Cartesian2(0.0, 0.0)
            });
            
            viewer.scene.globe.material = gridMaterial;
            
            updateStatus('Globe configured');
            
            // Position camera 10km above Zurich
            viewer.camera.setView({
                destination: Cesium.Cartesian3.fromDegrees(8.5417, 47.3769, 10000),
                orientation: {
                    heading: 0.0,
                    pitch: Cesium.Math.toRadians(-45),
                    roll: 0.0
                }
            });
            
            updateStatus('Camera positioned');
            
            // Add a red marker at Zurich
            viewer.entities.add({
                name: 'Zurich',
                position: Cesium.Cartesian3.fromDegrees(8.5417, 47.3769, 100),
                point: {
                    pixelSize: 10,
                    color: Cesium.Color.RED,
                    outlineColor: Cesium.Color.WHITE,
                    outlineWidth: 2,
                    heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND
                },
                label: {
                    text: 'Zurich',
                    font: '14pt sans-serif',
                    style: Cesium.LabelStyle.FILL_AND_OUTLINE,
                    outlineWidth: 2,
                    verticalOrigin: Cesium.VerticalOrigin.BOTTOM,
                    pixelOffset: new Cesium.Cartesian2(0, -15)
                }
            });
            
            updateStatus('SUCCESS: Blue globe with grid at Zurich');
            
            // Log success
            console.log('Cesium initialized successfully:', {
                camera: viewer.camera.positionCartographic,
                globe: viewer.scene.globe ? 'exists' : 'missing',
                entities: viewer.entities.values.length
            });
            
        } catch (error) {
            const errorMsg = 'ERROR: ' + error.message;
            updateStatus(errorMsg);
            console.error('Cesium initialization failed:', error);
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