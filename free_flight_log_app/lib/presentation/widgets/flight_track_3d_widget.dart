import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import '../../data/models/flight.dart';
import '../../data/models/igc_file.dart';
import '../../services/igc_import_service.dart';
import '../../services/logging_service.dart';

class FlightTrack3DWidget extends StatefulWidget {
  final Flight flight;
  final bool showControls;
  
  const FlightTrack3DWidget({
    super.key,
    required this.flight,
    this.showControls = true,
  });

  @override
  State<FlightTrack3DWidget> createState() => _FlightTrack3DWidgetState();
}

class _FlightTrack3DWidgetState extends State<FlightTrack3DWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _error;
  List<IgcPoint> _trackPoints = [];
  
  // Add IGC service
  final IgcImportService _igcService = IgcImportService();

  @override
  void initState() {
    super.initState();
    _loadTrackData();
  }

  Future<void> _loadTrackData() async {
    if (widget.flight.trackLogPath == null) {
      _initializeWebView(); // No track data, just show terrain
      return;
    }

    try {
      final trackPoints = await _igcService.getTrackPoints(widget.flight.trackLogPath!);
      setState(() {
        _trackPoints = trackPoints;
      });
      _initializeWebView();
    } catch (e) {
      LoggingService.error('FlightTrack3DWidget: Error loading track data', e);
      setState(() {
        _error = 'Error loading track data: $e';
        _isLoading = false;
      });
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _error = null;
            });
            LoggingService.debug('FlightTrack3DWidget: WebView page started loading');
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            LoggingService.debug('FlightTrack3DWidget: WebView page finished loading');
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _error = 'Failed to load 3D view: ${error.description}';
              _isLoading = false;
            });
            LoggingService.error('FlightTrack3DWidget: WebView resource error', error.description);
          },
        ),
      )
      ..loadHtmlString(_buildCesiumWithTerrainHTML());
  }

  String _buildCesiumWithTerrainHTML() {
    final trackJson = _trackPoints.isNotEmpty 
        ? jsonEncode(_trackPoints.map((p) => {
            'lat': p.latitude,
            'lon': p.longitude,
            'alt': p.gpsAltitude,
            'time': p.timestamp.millisecondsSinceEpoch,
          }).toList())
        : '[]';

    LoggingService.debug('FlightTrack3DWidget: Building Cesium HTML with ${_trackPoints.length} track points');

    return '''
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, minimum-scale=1, user-scalable=no">
        <title>Flight Track 3D</title>
        <script src="https://cesium.com/downloads/cesiumjs/releases/1.111/Build/Cesium/Cesium.js"></script>
        <link href="https://cesium.com/downloads/cesiumjs/releases/1.111/Build/Cesium/Widgets/widgets.css" rel="stylesheet">
        <style>
            html, body, #cesiumContainer {
                width: 100%; height: 100%; margin: 0; padding: 0; overflow: hidden;
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            }
            .loading {
                position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%);
                color: white; font-size: 16px; z-index: 1000; text-align: center;
                background: rgba(0,0,0,0.7); padding: 20px; border-radius: 8px;
            }
            .error {
                position: absolute; top: 20px; left: 20px; right: 20px;
                background: rgba(255,0,0,0.9); color: white; padding: 15px; border-radius: 8px;
                font-size: 14px; z-index: 1000;
            }
        </style>
    </head>
    <body>
        <div id="loading" class="loading">
            <div>Loading 3D terrain...</div>
            <div style="font-size: 12px; margin-top: 8px; opacity: 0.8;">This may take a moment</div>
        </div>
        <div id="cesiumContainer"></div>
        
        <script>
            console.log('Starting enhanced Cesium initialization...');
            
            try {
                // Create viewer without terrain provider first (will add after)
                const viewer = new Cesium.Viewer('cesiumContainer', {
                    
                    // Mobile-optimized UI - hide everything for clean view
                    scene3DOnly: true,
                    shouldAnimate: false,
                    homeButton: false,
                    sceneModePicker: false,
                    baseLayerPicker: false,
                    navigationHelpButton: false,
                    animation: false,
                    timeline: false,
                    fullscreenButton: false,
                    vrButton: false,
                    geocoder: false,
                    infoBox: false,
                    selectionIndicator: false,
                    
                    // Performance settings for mobile
                    requestRenderMode: true,
                    maximumRenderTimeChange: Infinity,
                });

                // Add world terrain using CesiumJS 1.111 API
                viewer.terrainProvider = new Cesium.CesiumTerrainProvider({
                    url: Cesium.IonResource.fromAssetId(1),  // Cesium World Terrain
                    requestWaterMask: false,
                    requestVertexNormals: false
                });

                // Optimize for mobile performance
                viewer.scene.fog.enabled = false;
                viewer.scene.skyAtmosphere.show = false;
                viewer.scene.globe.enableLighting = false;
                viewer.scene.globe.showGroundAtmosphere = false;

                console.log('Cesium viewer created successfully with terrain');

                // Load flight track data
                const trackData = $trackJson;
                console.log('Track data loaded:', trackData.length, 'points');

                if (trackData.length > 0) {
                    console.log('Adding flight track to scene...');
                    
                    // Convert track points to Cesium positions
                    const positions = trackData.map(point => 
                        Cesium.Cartesian3.fromDegrees(point.lon, point.lat, point.alt)
                    );

                    // Add flight track as bright yellow polyline
                    const flightTrackEntity = viewer.entities.add({
                        name: 'Flight Track',
                        polyline: {
                            positions: positions,
                            width: 4,
                            material: Cesium.Color.YELLOW.withAlpha(0.9),
                            clampToGround: false,
                            extrudedHeight: 0,
                        }
                    });

                    console.log('Flight track added to scene');

                    // Add launch marker (green)
                    const launch = trackData[0];
                    viewer.entities.add({
                        name: 'Launch',
                        position: Cesium.Cartesian3.fromDegrees(launch.lon, launch.lat, launch.alt + 10),
                        point: {
                            pixelSize: 12,
                            color: Cesium.Color.LIME,
                            outlineColor: Cesium.Color.WHITE,
                            outlineWidth: 2,
                            heightReference: Cesium.HeightReference.NONE
                        },
                        label: {
                            text: 'LAUNCH',
                            font: '12px sans-serif',
                            fillColor: Cesium.Color.WHITE,
                            outlineColor: Cesium.Color.BLACK,
                            outlineWidth: 2,
                            pixelOffset: new Cesium.Cartesian2(0, -30),
                            scale: 0.8
                        }
                    });

                    // Add landing marker (red)
                    const landing = trackData[trackData.length - 1];
                    viewer.entities.add({
                        name: 'Landing',
                        position: Cesium.Cartesian3.fromDegrees(landing.lon, landing.lat, landing.alt + 10),
                        point: {
                            pixelSize: 12,
                            color: Cesium.Color.RED,
                            outlineColor: Cesium.Color.WHITE,
                            outlineWidth: 2,
                            heightReference: Cesium.HeightReference.NONE
                        },
                        label: {
                            text: 'LANDING',
                            font: '12px sans-serif',
                            fillColor: Cesium.Color.WHITE,
                            outlineColor: Cesium.Color.BLACK,
                            outlineWidth: 2,
                            pixelOffset: new Cesium.Cartesian2(0, -30),
                            scale: 0.8
                        }
                    });

                    console.log('Launch and landing markers added');

                    // Fit camera to track with nice viewing angle
                    setTimeout(() => {
                        try {
                            viewer.zoomTo(flightTrackEntity, new Cesium.HeadingPitchRange(
                                Cesium.Math.toRadians(0),      // heading: north
                                Cesium.Math.toRadians(-30),    // pitch: looking down 30 degrees
                                Math.max(5000, trackData.length * 2) // distance: scale with track size
                            ));
                            console.log('Camera fitted to track');
                        } catch (e) {
                            console.error('Error fitting camera to track:', e);
                        }
                    }, 1000);

                } else {
                    console.log('No track data available, showing default view');
                    // Default view of Alps for paragliding context
                    viewer.camera.setView({
                        destination: Cesium.Cartesian3.fromDegrees(8.2319, 46.8182, 10000), // Switzerland
                        orientation: {
                            heading: Cesium.Math.toRadians(0),
                            pitch: Cesium.Math.toRadians(-30),
                            roll: 0.0
                        }
                    });
                }

                // Hide loading indicator
                setTimeout(() => {
                    const loading = document.getElementById('loading');
                    if (loading) {
                        loading.style.display = 'none';
                    }
                    console.log('Loading indicator hidden - Cesium scene ready');
                }, 2000); // Give terrain time to load

            } catch (error) {
                console.error('Cesium initialization failed:', error);
                const loading = document.getElementById('loading');
                if (loading) {
                    loading.className = 'error';
                    loading.innerHTML = 'Error loading 3D view:<br>' + error.message + '<br><br>Please check internet connection';
                }
            }
        </script>
    </body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[100],
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                '3D View Error',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  _loadTrackData();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Initializing 3D View...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Loading terrain and flight data',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}