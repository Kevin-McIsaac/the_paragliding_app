import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> 
    with WidgetsBindingObserver {
  InAppWebViewController? webViewController;
  bool isLoading = true;
  bool _isDisposed = false;
  Timer? _memoryMonitorTimer;
  
  @override
  void initState() {
    super.initState();
    // Add lifecycle observer for proper resource management
    WidgetsBinding.instance.addObserver(this);
    
    // Start memory monitoring in debug mode
    if (kDebugMode) {
      _startMemoryMonitoring();
    }
  }
  
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
            
            // Memory optimization settings
            cacheMode: CacheMode.LOAD_NO_CACHE,  // Don't cache in WebView
            domStorageEnabled: false,  // Disable DOM storage for memory savings
            databaseEnabled: false,  // Disable database storage
            clearSessionCache: true,  // Clear cache on load
            
            // Performance settings
            thirdPartyCookiesEnabled: false,  // Disable third-party cookies
            allowContentAccess: true,
            useHybridComposition: true,
            hardwareAcceleration: true,
            
            // iOS-specific settings
            allowsInlineMediaPlayback: true,
            allowsAirPlayForMediaPlayback: false,  // Disable AirPlay to save memory
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
    
    // Determine if in debug mode for conditional logging
    final bool isDebugMode = kDebugMode;
    
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
        // Debug mode flag from Flutter
        const DEBUG_MODE = $isDebugMode;
        
        // Logging wrapper for conditional output
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
        
        // Cesium Ion token
        Cesium.Ion.defaultAccessToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiIzYzkwM2EwNS00YjU2LTRiMzEtYjE3NC01ODlkYWM3MjMzNmEiLCJpZCI6MzMwMjc0LCJpYXQiOjE3NTQ3MjUxMjd9.IizVx3Z5iR9Xe1TbswK-FKidO9UoWa5pqa4t66NK8W0";
        
        cesiumLog.info('Starting Cesium initialization...');
        
        try {
            // Aggressively optimized Cesium viewer settings for minimal memory usage
            const viewer = new Cesium.Viewer("cesiumContainer", {
                terrain: Cesium.Terrain.fromWorldTerrain({
                    requestWaterMask: false,  // Disable water effects
                    requestVertexNormals: false,  // Disable lighting calculations
                    requestMetadata: false  // Disable metadata
                }),
                scene3DOnly: true,  // Disable 2D/Columbus view modes for performance
                requestRenderMode: true,  // Only render on demand
                maximumRenderTimeChange: Infinity,  // Reduce re-renders
                targetFrameRate: 30,  // Balanced frame rate
                resolutionScale: 0.85,  // Better quality while still saving memory
                
                // WebGL context options for low memory usage
                contextOptions: {
                    webgl: {
                        powerPreference: 'low-power',  // Use low-power GPU
                        antialias: false,  // Disable antialiasing
                        preserveDrawingBuffer: false,
                        failIfMajorPerformanceCaveat: true,
                        depth: true,
                        stencil: false,
                        alpha: false
                    }
                },
                
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
            
            cesiumLog.debug('Cesium viewer created, configuring aggressive memory optimizations...');
            
            // Configure scene for minimal memory usage
            viewer.scene.globe.enableLighting = false;
            viewer.scene.globe.showGroundAtmosphere = false;  // Disable atmosphere
            viewer.scene.fog.enabled = false;  // Disable fog
            viewer.scene.globe.depthTestAgainstTerrain = false;  // Faster rendering
            viewer.scene.screenSpaceCameraController.enableCollisionDetection = false;
            
            // Moderate tile cache for better quality
            viewer.scene.globe.tileCacheSize = 40;  // Balanced cache size
            viewer.scene.globe.preloadSiblings = false;  // Don't preload adjacent tiles
            viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles
            
            // Balanced screen space error for decent quality with good performance
            viewer.scene.globe.maximumScreenSpaceError = 3;  // Balanced quality vs performance
            
            // Moderate texture size limit
            viewer.scene.maximumTextureSize = 2048;  // Better texture quality
            
            // Disable terrain exaggeration
            viewer.scene.globe.terrainExaggeration = 1.0;
            viewer.scene.globe.terrainExaggerationRelativeHeight = 0.0;
            
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
            
            // Track initial load with minimal logging
            let initialLoadComplete = false;
            let lastTileCount = -1;
            const loadingStartTime = Date.now();
            
            const tileLoadHandler = function(queuedTileCount) {
                if (queuedTileCount === 0 && !initialLoadComplete) {
                    initialLoadComplete = true;
                    const loadTime = ((Date.now() - loadingStartTime) / 1000).toFixed(2);
                    cesiumLog.info('Initial tile load complete in ' + loadTime + 's');
                    document.getElementById('loadingOverlay').style.display = 'none';
                    
                    // Remove the listener after initial load
                    viewer.scene.globe.tileLoadProgressEvent.removeEventListener(tileLoadHandler);
                } else if (DEBUG_MODE && !initialLoadComplete) {
                    // Only log significant changes in debug mode
                    const change = Math.abs(lastTileCount - queuedTileCount);
                    if (change > 10 || (queuedTileCount === 0 && lastTileCount > 0)) {
                        cesiumLog.debug('Tiles queued: ' + queuedTileCount);
                        lastTileCount = queuedTileCount;
                    }
                }
            };
            viewer.scene.globe.tileLoadProgressEvent.addEventListener(tileLoadHandler);
            
            // Setup periodic memory cleanup
            let cleanupTimer = setInterval(() => {
                if (viewer && viewer.scene) {
                    // Force garbage collection of unused tiles
                    viewer.scene.globe.tileCache.trim();
                    
                    // Compact tile cache if it grows too large
                    if (viewer.scene.globe.tileCache.count > 15) {
                        cesiumLog.debug('Trimming tile cache');
                        viewer.scene.globe.tileCache.reset();
                    }
                    
                    // Clear any accumulated primitives
                    if (viewer.scene.primitives.length > 10) {
                        viewer.scene.primitives.removeAll();
                    }
                }
            }, 30000);  // Every 30 seconds
            
            cesiumLog.info('Cesium viewer initialized successfully');
            cesiumLog.debug('Camera position: lat=$lat, lon=$lon, altitude=$altitude');
            
            // Store viewer globally for cleanup
            window.viewer = viewer;
            
        } catch (error) {
            cesiumLog.error('Initialization error: ' + error.message);
            if (DEBUG_MODE) {
                cesiumLog.error('Stack: ' + error.stack);
            }
            document.getElementById('loadingOverlay').innerHTML = 'Error loading Cesium: ' + error.message;
        }
        
        // Cleanup function to be called from Flutter before disposal
        function cleanupCesium() {
            cesiumLog.debug('Cleaning up Cesium resources...');
            
            // Clear the cleanup timer
            if (typeof cleanupTimer !== 'undefined') {
                clearInterval(cleanupTimer);
            }
            
            if (window.viewer) {
                try {
                    // Remove all entities, data sources, and primitives
                    viewer.scene.primitives.removeAll();
                    viewer.entities.removeAll();
                    viewer.dataSources.removeAll();
                    viewer.imageryLayers.removeAll();
                    
                    // Clear tile cache
                    viewer.scene.globe.tileCache.reset();
                    
                    // Destroy the viewer
                    viewer.destroy();
                    window.viewer = null;
                    
                    cesiumLog.debug('Cesium cleanup completed');
                } catch (e) {
                    cesiumLog.error('Error during cleanup: ' + e.message);
                }
            }
        }
        
        // Memory monitoring function
        function checkMemory() {
            if (window.performance && window.performance.memory) {
                const memory = window.performance.memory;
                const usage = {
                    used: Math.round(memory.usedJSHeapSize / 1048576),
                    total: Math.round(memory.totalJSHeapSize / 1048576),
                    limit: Math.round(memory.jsHeapSizeLimit / 1048576)
                };
                
                if (usage.used > usage.total * 0.8) {
                    // High memory usage - trigger cleanup
                    cesiumLog.debug('High memory usage detected: ' + usage.used + 'MB, triggering cleanup');
                    if (window.viewer) {
                        viewer.scene.globe.tileCache.trim();
                        viewer.scene.primitives.removeAll();
                    }
                }
                
                return usage;
            }
            return null;
        }
        
        // Also cleanup on page unload
        window.addEventListener('beforeunload', function() {
            cleanupCesium();
        });
        
        // Handle visibility changes to pause/resume rendering
        document.addEventListener('visibilitychange', function() {
            if (window.viewer) {
                if (document.hidden) {
                    viewer.scene.requestRenderMode = true;
                    viewer.scene.maximumRenderTimeChange = Infinity;
                    cesiumLog.debug('Page hidden - rendering paused');
                } else {
                    viewer.scene.requestRenderMode = false;
                    cesiumLog.debug('Page visible - rendering resumed');
                }
            }
        });
    </script>
</body>
</html>
    ''';
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _memoryMonitorTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _disposeWebView();
    super.dispose();
  }
  
  Future<void> _disposeWebView() async {
    if (webViewController != null) {
      try {
        // Call JavaScript cleanup function before disposing
        await webViewController!.evaluateJavascript(source: '''
          if (typeof cleanupCesium === 'function') {
            cleanupCesium();
          }
        ''');
        
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
        
        LoggingService.debug('Cesium3D: WebView disposed successfully');
      } catch (e) {
        LoggingService.error('Cesium3D Disposal', 'Error disposing WebView: $e');
      }
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_isDisposed) return;
    
    switch (state) {
      case AppLifecycleState.paused:
        // Pause WebView when app goes to background
        webViewController?.pauseTimers();
        LoggingService.debug('Cesium3D: App paused - WebView timers paused');
        break;
      case AppLifecycleState.resumed:
        // Resume WebView when app comes to foreground
        if (!_isDisposed && webViewController != null) {
          webViewController!.resumeTimers();
          LoggingService.debug('Cesium3D: App resumed - WebView timers resumed');
        }
        break;
      case AppLifecycleState.detached:
        // Clean up resources when app is detached
        _disposeWebView();
        break;
      default:
        break;
    }
  }
  
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    
    if (_isDisposed || webViewController == null) return;
    
    LoggingService.warning('Cesium3D: Memory pressure detected - aggressive cleanup');
    
    // Clear WebView cache on memory pressure
    webViewController?.clearCache();
    
    // Force aggressive garbage collection in JavaScript
    webViewController?.evaluateJavascript(source: '''
      if (window.viewer) {
        // Clear all resources
        viewer.scene.primitives.removeAll();
        viewer.entities.removeAll();
        viewer.dataSources.removeAll();
        
        // Reset tile cache completely
        viewer.scene.globe.tileCache.reset();
        
        // Reduce cache size further
        viewer.scene.globe.tileCacheSize = 10;
        
        // Force JavaScript garbage collection if available
        if (window.gc) {
          window.gc();
        }
        
        cesiumLog.info('Memory pressure: Aggressive cleanup completed');
      }
    ''');
  }
  
  void _startMemoryMonitoring() {
    _memoryMonitorTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isDisposed || webViewController == null) {
        timer.cancel();
        return;
      }
      
      // Check memory usage via JavaScript
      webViewController?.evaluateJavascript(source: '''
        if (typeof checkMemory === 'function') {
          const usage = checkMemory();
          if (usage) {
            cesiumLog.debug('Memory: ' + usage.used + 'MB / ' + usage.total + 'MB (limit: ' + usage.limit + 'MB)');
          }
        }
      ''');
    });
  }
}