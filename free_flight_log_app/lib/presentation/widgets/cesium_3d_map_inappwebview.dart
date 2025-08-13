import 'dart:async';
import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../services/logging_service.dart';
import '../../services/preferences_service.dart';
import '../../config/cesium_config.dart';

class Cesium3DMapInAppWebView extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final double? initialAltitude;
  final List<dynamic>? trackPoints;
  final void Function(InAppWebViewController)? onControllerCreated;
  
  const Cesium3DMapInAppWebView({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialAltitude,
    this.trackPoints,
    this.onControllerCreated,
  });

  @override
  State<Cesium3DMapInAppWebView> createState() => _Cesium3DMapInAppWebViewState();
}

class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> 
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  InAppWebViewController? webViewController;
  bool isLoading = true;
  bool _isDisposed = false;
  Timer? _memoryMonitorTimer;
  int _loadRetryCount = 0;
  final int _maxRetries = 3;
  bool _showErrorMessage = false;
  String _errorMessage = '';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _hasInternet = true;
  bool _isWebViewReady = false;
  int _surfaceErrorCount = 0;
  Timer? _surfaceRecoveryTimer;
  
  // Cancellation tokens for async operations
  CancelableOperation<void>? _htmlLoadOperation;
  CancelableOperation<void>? _connectivityCheckOperation;
  CancelableOperation<void>? _webViewDisposeOperation;
  
  // Keep widget alive to prevent surface recreation
  @override
  bool get wantKeepAlive => true;
  
  String? _cesiumHtml;
  bool _htmlLoadError = false;
  
  // Preferences service
  final PreferencesService _preferencesService = PreferencesService();
  
  // Saved preferences
  String _savedSceneMode = PreferencesService.sceneMode3D;
  String _savedBaseMap = 'Bing Maps Aerial';
  bool _savedTerrainEnabled = true;
  bool _savedNavigationHelpDialogOpen = false;
  
  @override
  void initState() {
    super.initState();
    // Add lifecycle observer for proper resource management
    WidgetsBinding.instance.addObserver(this);
    
    // Load saved preferences
    _loadPreferences();
    
    // Load HTML template from assets with cancellation support
    _htmlLoadOperation = CancelableOperation.fromFuture(
      _loadCesiumHtml(),
    );
    
    // Check connectivity asynchronously with cancellation support
    _connectivityCheckOperation = CancelableOperation.fromFuture(
      _checkConnectivity(),
    );
    
    // Listen for connectivity changes
    _connectivitySubscription = Connectivity()
      .onConnectivityChanged
      .listen(_updateConnectionStatus);
    
    // Initialize WebView immediately for faster loading
    _isWebViewReady = true;
    
    // Start memory monitoring in debug mode with delay
    if (kDebugMode) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isDisposed) {
          _startMemoryMonitoring();
        }
      });
    }
  }
  
  Future<void> _loadPreferences() async {
    try {
      final sceneMode = await _preferencesService.getSceneMode();
      final baseMap = await _preferencesService.getBaseMap();
      final terrainEnabled = await _preferencesService.getTerrainEnabled();
      final navigationHelpDialogOpen = await _preferencesService.getNavigationHelpDialogOpen();
      
      if (mounted && !_isDisposed) {
        setState(() {
          _savedSceneMode = sceneMode;
          _savedBaseMap = baseMap;
          _savedTerrainEnabled = terrainEnabled;
          _savedNavigationHelpDialogOpen = navigationHelpDialogOpen;
        });
        
        LoggingService.debug('Cesium3D: Loaded preferences - Scene: $sceneMode, BaseMap: $baseMap, Terrain: $terrainEnabled, NavDialog: $navigationHelpDialogOpen');
      }
    } catch (e) {
      LoggingService.error('Cesium3D', 'Failed to load preferences: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // Show offline message if no internet
    if (!_hasInternet) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.wifi_off,
                size: 64,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                'No Internet Connection',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The 3D map requires an active internet connection\nto load terrain and imagery data',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _checkConnectivity,
                icon: const Icon(Icons.refresh),
                label: const Text('Check Connection'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading while HTML is being loaded from assets
    if (_cesiumHtml == null && !_htmlLoadError) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    // Show error if HTML failed to load
    if (_htmlLoadError) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load map resources',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to load Cesium map assets',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Wrap in Visibility to maintain state when hidden
    return Visibility(
      visible: true,
      maintainState: true,  // Keep state when hidden
      maintainAnimation: true,
      maintainSize: false,
      child: Stack(
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
            
            // Surface handling settings
            useHybridComposition: true,  // Use hybrid composition for better surface handling
            hardwareAcceleration: true,
            supportMultipleWindows: false,
            useWideViewPort: false,
            
            // iOS-specific settings
            allowsInlineMediaPlayback: true,
            allowsAirPlayForMediaPlayback: false,  // Disable AirPlay to save memory
          ),
          onWebViewCreated: (controller) {
            if (!_isDisposed) {
              webViewController = controller;
              LoggingService.debug('Cesium3D Surface: WebView created');
              _surfaceErrorCount = 0; // Reset surface error count
              
              // Add JavaScript handlers for scene mode changes
              controller.addJavaScriptHandler(
                handlerName: 'onSceneModeChanged',
                callback: (args) async {
                  if (args.isNotEmpty) {
                    final sceneMode = args[0] as String;
                    LoggingService.info('Cesium3D: Scene mode changed to $sceneMode');
                    
                    // Save the preference to Flutter side
                    await _preferencesService.setSceneMode(sceneMode);
                  }
                },
              );
              
              // Add handler for imagery provider changes
              controller.addJavaScriptHandler(
                handlerName: 'onImageryProviderChanged',
                callback: (args) async {
                  if (args.isNotEmpty) {
                    final imageryName = args[0] as String;
                    LoggingService.info('Cesium3D: Imagery provider changed to $imageryName');
                    
                    // Save the preference
                    await _preferencesService.setBaseMap(imageryName);
                    _savedBaseMap = imageryName;
                  }
                },
              );
              
              // Add handler for terrain provider changes
              controller.addJavaScriptHandler(
                handlerName: 'onTerrainProviderChanged',
                callback: (args) async {
                  if (args.isNotEmpty) {
                    final terrainEnabled = args[0] as bool;
                    LoggingService.info('Cesium3D: Terrain changed to ${terrainEnabled ? "enabled" : "disabled"}');
                    
                    // Save the preference
                    await _preferencesService.setTerrainEnabled(terrainEnabled);
                    _savedTerrainEnabled = terrainEnabled;
                  }
                },
              );
              
              // Add handler for navigation help dialog state changes
              controller.addJavaScriptHandler(
                handlerName: 'onNavigationHelpDialogStateChanged',
                callback: (args) async {
                  if (args.isNotEmpty) {
                    final isOpen = args[0] as bool;
                    LoggingService.info('Cesium3D: Navigation help dialog ${isOpen ? "opened" : "closed"}');
                    
                    // Save the preference
                    await _preferencesService.setNavigationHelpDialogOpen(isOpen);
                    _savedNavigationHelpDialogOpen = isOpen;
                  }
                },
              );
              
              // Notify parent widget of controller creation
              if (widget.onControllerCreated != null) {
                widget.onControllerCreated!(controller);
              }
            }
          },
          onLoadStop: (controller, url) async {
            if (!_isDisposed) {
              LoggingService.debug('Cesium3D Surface: Load complete');
              if (mounted) {
                setState(() {
                  isLoading = false;
                  _loadRetryCount = 0; // Reset retry count on successful load
                  _surfaceErrorCount = 0; // Reset surface errors on successful load
                });
                
                // Track is now loaded during initialization, no need to load here
              }
            }
          },
          onConsoleMessage: (controller, consoleMessage) {
            // Reduce console logging overhead
            if (!kDebugMode && consoleMessage.messageLevel != ConsoleMessageLevel.ERROR) {
              return; // Only log errors in release mode
            }
            
            // Skip repetitive messages
            final msg = consoleMessage.message;
            if (msg.contains('Tiles queued') || 
                msg.contains('Memory:') || 
                msg.contains('Debug')) {
              return; // Skip verbose debug messages
            }
            
            final level = consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ? 'ERROR' :
                         consoleMessage.messageLevel == ConsoleMessageLevel.WARNING ? 'WARNING' :
                         consoleMessage.messageLevel == ConsoleMessageLevel.LOG ? 'LOG' : 'DEBUG';
            
            if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
              LoggingService.error('Cesium3D JS', msg);
            } else if (kDebugMode) {
              LoggingService.debug('Cesium3D JS [$level]: $msg');
            }
          },
          onLoadError: (controller, url, code, message) {
            // Categorize errors
            if (message.contains('ERR_CONNECTION_REFUSED')) {
              if (kDebugMode && url.toString().contains('localhost')) {
                // Development server not accessible from WebView (expected)
                LoggingService.debug('WebView cannot access Flutter dev server (expected)');
              } else {
                // Production connection issue
                LoggingService.error('Cesium3D', 'Network connection failed: $message');
                _handleLoadError(url.toString(), message);
              }
            } else if (message.contains('ERR_INTERNET_DISCONNECTED')) {
              LoggingService.error('Cesium3D', 'No internet connection available');
              _handleNoInternet();
            } else {
              LoggingService.error('Cesium3D', 'Load error: $message (code: $code)');
              _handleLoadError(url.toString(), message);
            }
          },
          onReceivedError: (controller, request, error) {
            // Ignore development server connection errors
            final errorDesc = error.description ?? '';
            final urlString = request.url?.toString() ?? '';
            
            if (errorDesc.contains('ERR_CONNECTION_REFUSED')) {
              if (kDebugMode && (urlString.contains('localhost') || urlString.contains('127.0.0.1'))) {
                // Skip logging for hot reload attempts - this is expected
                return;
              }
              // Log actual connection issues
              LoggingService.error('Cesium3D', 'Connection refused: $urlString');
            } else if (!errorDesc.contains('ERR_INTERNET_DISCONNECTED')) {
              // Log other errors except internet disconnection (handled elsewhere)
              LoggingService.error('Cesium3D InAppWebView', 
                'Received error: $errorDesc');
            }
          },
          onReceivedHttpError: (controller, request, response) {
            // Ignore development server 404s
            if (kDebugMode && 
                request.url.toString().contains('localhost') &&
                response.statusCode == 404) {
              return;
            }
            
            LoggingService.error('Cesium3D InAppWebView', 
              'HTTP error: ${response.statusCode} - ${response.reasonPhrase}');
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
        if (_showErrorMessage)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.shade700,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load 3D map',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _retryLoad,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _loadCesiumHtml() async {
    try {
      // Check if operation was cancelled
      if (_isDisposed) return;
      
      // Load HTML template and JavaScript from assets
      final htmlTemplate = await rootBundle.loadString('assets/cesium/cesium.html');
      
      // Check cancellation after first async operation
      if (_isDisposed) return;
      
      final jsContent = await rootBundle.loadString('assets/cesium/cesium.js');
      
      // Check cancellation after second async operation
      if (_isDisposed) return;
      
      // Inject JavaScript content into HTML template
      final htmlWithJs = htmlTemplate.replaceAll('{{JS_CONTENT}}', jsContent);
      
      // Store the loaded HTML for use
      if (mounted && !_isDisposed) {
        setState(() {
          _cesiumHtml = htmlWithJs;
        });
      }
      
      LoggingService.debug('Cesium3D: Loaded HTML and JS assets successfully');
    } catch (e) {
      if (_isDisposed) return; // Ignore errors if cancelled
      
      LoggingService.error('Cesium3D', 'Failed to load HTML assets: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _htmlLoadError = true;
        });
      }
    }
  }
  
  String _buildCesiumHtml() {
    // Use provided coordinates or default to Switzerland (typical paragliding area)
    final lat = widget.initialLat ?? 46.8182;
    final lon = widget.initialLon ?? 8.2275;
    final altitude = widget.initialAltitude ?? 2000000; // 2000km altitude for good view
    
    // Determine if in debug mode for conditional logging
    final bool isDebugMode = kDebugMode;
    
    // Convert track points to JavaScript array format if available
    String trackPointsJs = '';
    if (widget.trackPoints != null && widget.trackPoints!.isNotEmpty) {
      final points = widget.trackPoints!.map((p) => 
        '{latitude:${p['latitude']},longitude:${p['longitude']},altitude:${p['altitude'] ?? p['gpsAltitude']},climbRate:${p['climbRate'] ?? 0},timestamp:"${p['timestamp'] ?? ""}",timezone:"${p['timezone'] ?? '+00:00'}"}'
      ).join(',');
      trackPointsJs = '[$points]';
    } else {
      trackPointsJs = '[]';
    }
    
    // If HTML template is loaded from assets, use it
    if (_cesiumHtml != null) {
      // Replace placeholders with actual values
      return _cesiumHtml!
        .replaceAll('{{LAT}}', lat.toString())
        .replaceAll('{{LON}}', lon.toString())
        .replaceAll('{{ALTITUDE}}', altitude.toString())
        .replaceAll('{{DEBUG}}', isDebugMode.toString())
        .replaceAll('{{TOKEN}}', CesiumConfig.ionAccessToken)
        .replaceAll('window.cesiumConfig = {', '''window.cesiumConfig = {
            trackPoints: $trackPointsJs,
            savedSceneMode: "$_savedSceneMode",
            savedBaseMap: "$_savedBaseMap",
            savedTerrainEnabled: $_savedTerrainEnabled,
            savedNavigationHelpDialogOpen: $_savedNavigationHelpDialogOpen,''');
    }
    
    // Fallback to inline HTML (keeping original implementation as backup)
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
        
        // Cesium Ion token (using config)
        Cesium.Ion.defaultAccessToken = "${CesiumConfig.ionAccessToken}";
        
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
            
            // Strict tile cache management to prevent memory limit warnings
            viewer.scene.globe.tileCacheSize = ${CesiumConfig.tileCacheSize};  // From config
            viewer.scene.globe.preloadSiblings = false;  // Don't preload adjacent tiles
            viewer.scene.globe.preloadAncestors = false;  // Don't preload parent tiles
            
            // Tile memory budget - set explicit memory limit for tiles
            viewer.scene.globe.maximumMemoryUsage = ${CesiumConfig.maximumMemoryUsageMB};  // From config
            
            // Balanced screen space error for decent quality with good performance
            viewer.scene.globe.maximumScreenSpaceError = ${CesiumConfig.maximumScreenSpaceError};  // From config
            
            // Moderate texture size limit
            viewer.scene.maximumTextureSize = ${CesiumConfig.maximumTextureSize};  // From config
            
            // Set explicit tile load limits
            viewer.scene.globe.loadingDescendantLimit = 10;  // Limit concurrent tile loads
            viewer.scene.globe.immediatelyLoadDesiredLevelOfDetail = false;  // Progressive loading
            
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
            
            // Handle tile memory exceeded events
            viewer.scene.globe.tileLoadProgressEvent.addEventListener(function() {
                // Monitor for memory issues
                const globe = viewer.scene.globe;
                if (globe._surface && globe._surface._tilesToRender) {
                    const tileCount = globe._surface._tilesToRender.length;
                    if (tileCount > 30) {
                        cesiumLog.debug('High tile count detected: ' + tileCount + ' - forcing cleanup');
                        // Use proper cache trimming method
                        if (globe._surface._tileProvider && globe._surface._tileProvider._tilesToRenderByTextureCount) {
                            globe._surface._tileProvider._tilesToRenderByTextureCount.trim();
                        }
                    }
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
            
            // Setup periodic memory cleanup with aggressive management
            let cleanupTimer = setInterval(() => {
                if (viewer && viewer.scene && viewer.scene.globe) {
                    // Check memory usage via performance API
                    if (window.performance && window.performance.memory) {
                        const memoryUsage = window.performance.memory.usedJSHeapSize;
                        if (memoryUsage > 100 * 1024 * 1024) {  // If over 100MB
                            cesiumLog.debug('High memory usage: ' + (memoryUsage / 1024 / 1024).toFixed(1) + 'MB - forcing cleanup');
                            
                            // Clear unused primitives and entities
                            viewer.scene.primitives.removeAll();
                            viewer.entities.removeAll();
                            
                            // Force garbage collection if available
                            if (window.gc) {
                                window.gc();
                            }
                        }
                    }
                    
                    // Monitor tile count for cleanup
                    if (viewer.scene.globe._surface && viewer.scene.globe._surface._tilesToRender) {
                        const tileCount = viewer.scene.globe._surface._tilesToRender.length;
                        if (tileCount > 25) {
                            cesiumLog.debug('High tile count: ' + tileCount + ' - reducing quality');
                            // Temporarily increase screen space error to reduce tile count
                            viewer.scene.globe.maximumScreenSpaceError = 6;
                            
                            // Reset after a delay
                            setTimeout(() => {
                                viewer.scene.globe.maximumScreenSpaceError = 4;
                            }, 5000);
                        }
                    }
                }
            }, 30000);  // Every 30 seconds for better memory management
            
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
            
            // Clear the cleanup timer first
            if (typeof cleanupTimer !== 'undefined') {
                clearInterval(cleanupTimer);
                cleanupTimer = undefined;
            }
            
            // Remove event listeners
            if (window.viewer && viewer.scene && viewer.scene.globe) {
                viewer.scene.globe.tileLoadProgressEvent.removeAllListeners();
            }
            
            if (window.viewer) {
                try {
                    // Stop rendering immediately
                    viewer.scene.requestRenderMode = true;
                    viewer.scene.maximumRenderTimeChange = 0;
                    
                    // Clear all data
                    if (viewer.scene && viewer.scene.primitives) {
                        viewer.scene.primitives.removeAll();
                    }
                    if (viewer.entities) {
                        viewer.entities.removeAll();
                    }
                    if (viewer.dataSources) {
                        viewer.dataSources.removeAll();
                    }
                    
                    // Clear tile cache
                    if (viewer.scene && viewer.scene.globe && viewer.scene.globe.tileCache) {
                        viewer.scene.globe.tileCache.reset();
                    }
                    
                    // Destroy the viewer safely
                    try {
                        viewer.destroy();
                    } catch (destroyError) {
                        cesiumLog.debug('Viewer destroy error (expected): ' + destroyError.message);
                    }
                    
                    window.viewer = null;
                    cesiumLog.debug('Cesium cleanup completed');
                } catch (e) {
                    cesiumLog.error('Error during cleanup: ' + e.message);
                    // Force clear the viewer reference even if cleanup fails
                    window.viewer = null;
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
    // Set disposed flag first to prevent any further operations
    _isDisposed = true;
    
    // Cancel all async operations
    _htmlLoadOperation?.cancel();
    _connectivityCheckOperation?.cancel();
    _webViewDisposeOperation?.cancel();
    
    // Cancel all timers
    _memoryMonitorTimer?.cancel();
    _surfaceRecoveryTimer?.cancel();
    
    // Cancel subscriptions
    _connectivitySubscription?.cancel();
    
    // Remove observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Schedule WebView disposal for next frame with cancellation support
    // This allows the widget tree to update properly before disposal
    _webViewDisposeOperation = CancelableOperation.fromFuture(
      Future.delayed(Duration.zero, () {
        if (!_isDisposed) {
          _disposeWebView();
        }
      }),
    );
    
    super.dispose();
  }
  
  Future<void> _disposeWebView() async {
    if (webViewController != null && !_isDisposed) {
      try {
        // Mark as disposed immediately to prevent multiple disposal attempts
        final controller = webViewController;
        webViewController = null;
        
        // Try JavaScript cleanup with timeout
        try {
          await controller!.evaluateJavascript(source: '''
            if (typeof cleanupCesium === 'function') {
              cleanupCesium();
            }
            // Stop any running timers
            if (typeof cleanupTimer !== 'undefined') {
              clearInterval(cleanupTimer);
            }
            // Clear viewer reference
            if (window.viewer) {
              window.viewer = null;
            }
          ''').timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {
              LoggingService.debug('Cesium3D: JavaScript cleanup timed out');
              return null;
            },
          );
        } catch (e) {
          // JavaScript cleanup failed, continue with disposal
          LoggingService.debug('Cesium3D: JavaScript cleanup skipped: $e');
        }
        
        // Try to stop loading with error handling
        try {
          await controller?.stopLoading().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {
              LoggingService.debug('Cesium3D: Stop loading timed out');
            },
          );
        } catch (e) {
          // stopLoading failed, continue
          LoggingService.debug('Cesium3D: Stop loading skipped: $e');
        }
        
        // Try to clear cache
        try {
          await controller?.clearCache().timeout(
            const Duration(milliseconds: 500),
            onTimeout: () {
              LoggingService.debug('Cesium3D: Clear cache timed out');
            },
          );
        } catch (e) {
          LoggingService.debug('Cesium3D: Clear cache skipped: $e');
        }
        
        // Dispose is not available in flutter_inappwebview, controller cleanup happens automatically
        // when the widget is removed from the widget tree
        
        LoggingService.debug('Cesium3D: WebView cleanup completed');
      } catch (e) {
        LoggingService.error('Cesium3D Disposal', 'Error during WebView cleanup: $e');
      }
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_isDisposed) return;
    
    // Log surface lifecycle for debugging
    if (kDebugMode) {
      LoggingService.debug('Cesium3D Surface: App lifecycle - $state');
    }
    
    switch (state) {
      case AppLifecycleState.paused:
        // Pause WebView when app goes to background
        webViewController?.pauseTimers();
        LoggingService.debug('Cesium3D Surface: App paused - WebView timers paused');
        break;
      case AppLifecycleState.resumed:
        // Resume WebView when app comes to foreground
        if (!_isDisposed && webViewController != null) {
          webViewController!.resumeTimers();
          LoggingService.debug('Cesium3D Surface: App resumed - WebView timers resumed');
          
          // Check for surface errors after resume
          _checkSurfaceHealth();
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
        
        // Reset tile cache completely (with null check)
        if (viewer.scene.globe.tileCache) {
          viewer.scene.globe.tileCache.reset();
        }
        
        // Reduce cache size and memory limits drastically (with safety checks)
        if (viewer.scene.globe) {
          viewer.scene.globe.tileCacheSize = 5;
          viewer.scene.globe.maximumMemoryUsage = 64;  // Reduce to 64MB
          viewer.scene.globe.maximumScreenSpaceError = 8;  // Lower quality to save memory
        }
        if (viewer.scene) {
          viewer.scene.maximumTextureSize = 512;  // Smaller textures
        }
        
        // Request render to apply new limits
        viewer.scene.requestRender();
        
        // Force JavaScript garbage collection if available
        if (window.gc) {
          window.gc();
        }
        
        cesiumLog.info('Memory pressure: Aggressive cleanup completed');
      }
    ''');
  }
  
  void _startMemoryMonitoring() {
    _memoryMonitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
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
  
  Future<void> _handleLoadError(String url, String error) async {
    // Only retry for actual Cesium resources, not dev server
    if (!error.contains('ERR_CONNECTION_REFUSED') || 
        !url.contains('localhost')) {
      
      if (_loadRetryCount < _maxRetries && !_isDisposed) {
        _loadRetryCount++;
        LoggingService.info('Retrying Cesium load (attempt $_loadRetryCount/$_maxRetries)');
        
        // Wait before retry with exponential backoff
        await Future.delayed(Duration(seconds: 2 * _loadRetryCount));
        
        // Check if disposed during the delay
        if (_isDisposed) return;
        
        // Reload the WebView
        if (mounted && webViewController != null && !_isDisposed) {
          webViewController!.reload();
        }
      } else if (!_isDisposed) {
        LoggingService.error('Cesium3D', 
          'Failed to load after $_maxRetries attempts');
        
        // Show error to user
        if (mounted && !_isDisposed) {
          setState(() {
            _showErrorMessage = true;
            _errorMessage = 'Unable to load the 3D map after $_maxRetries attempts.\nPlease check your internet connection.';
          });
        }
      }
    }
  }
  
  void _handleNoInternet() {
    if (mounted) {
      setState(() {
        _showErrorMessage = true;
        _errorMessage = 'No internet connection available.\nThe 3D map requires an active internet connection.';
      });
    }
  }
  
  void _retryLoad() {
    setState(() {
      _showErrorMessage = false;
      _errorMessage = '';
      _loadRetryCount = 0;
      isLoading = true;
    });
    webViewController?.reload();
  }
  
  Future<void> _checkConnectivity() async {
    try {
      if (_isDisposed) return;
      
      final result = await Connectivity().checkConnectivity();
      
      if (_isDisposed) return;
      
      _updateConnectionStatus(result);
    } catch (e) {
      if (_isDisposed) return;
      
      LoggingService.error('Cesium3D', 'Error checking connectivity: $e');
      // Assume connected if we can't check
      if (mounted && !_isDisposed) {
        setState(() {
          _hasInternet = true;
        });
      }
    }
  }
  
  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final hasConnection = results.isNotEmpty && 
                         !results.contains(ConnectivityResult.none);
    
    if (mounted) {
      setState(() {
        _hasInternet = hasConnection;
      });
      
      if (!hasConnection) {
        LoggingService.warning('Cesium3D: No internet connection detected');
      } else if (!_hasInternet && hasConnection) {
        LoggingService.info('Cesium3D: Internet connection restored');
        // Reload if we regained connection and had an error
        if (_showErrorMessage) {
          _retryLoad();
        }
      }
    }
  }
  
  void _checkSurfaceHealth() {
    // Monitor for surface sync errors
    if (_surfaceErrorCount > 0) {
      LoggingService.warning('Cesium3D Surface: Detected $_surfaceErrorCount surface errors');
      
      if (_surfaceErrorCount > 3) {
        _handleSurfaceError();
      }
    }
  }
  
  Future<void> _loadFlightTrack(InAppWebViewController controller) async {
    try {
      // Wait a bit for Cesium to fully initialize
      await Future.delayed(const Duration(seconds: 3));
      
      LoggingService.debug('Cesium3D: Loading flight track with ${widget.trackPoints!.length} points');
      
      // Convert track points to JavaScript format
      final jsPoints = widget.trackPoints!.map((point) {
        // Handle Map objects (which is what we're getting from flight_track_widget)
        double lat, lon, alt, climbRate;
        String timezone, timestamp;
        
        if (point is Map) {
          lat = (point['latitude'] ?? 0.0).toDouble();
          lon = (point['longitude'] ?? 0.0).toDouble();
          alt = (point['altitude'] ?? 0.0).toDouble();
          climbRate = (point['climbRate'] ?? 0.0).toDouble();
          timezone = point['timezone'] ?? '+00:00';
          timestamp = point['timestamp'] ?? '';
        } else {
          // Handle object with properties
          lat = (point.latitude ?? 0.0).toDouble();
          lon = (point.longitude ?? 0.0).toDouble();
          alt = (point.altitude ?? 0.0).toDouble();
          climbRate = (point.climbRate ?? 0.0).toDouble();
          timezone = point.timezone ?? '+00:00';
          timestamp = point.timestamp ?? '';
        }
        
        return '{latitude:$lat,longitude:$lon,altitude:$alt,climbRate:$climbRate,timestamp:"$timestamp",timezone:"$timezone"}';
      }).join(',');
      
      // Log first and last points for debugging
      if (widget.trackPoints!.isNotEmpty) {
        final first = widget.trackPoints!.first;
        final last = widget.trackPoints!.last;
        LoggingService.debug('Cesium3D: First point: $first');
        LoggingService.debug('Cesium3D: Last point: $last');
      }
      
      // Call JavaScript function to create colored flight track
      final jsCode = '''
        if (typeof createColoredFlightTrack === 'function') {
          createColoredFlightTrack([$jsPoints]);
          console.log('[Cesium] Called createColoredFlightTrack with ${widget.trackPoints!.length} points');
        } else {
          console.error('[Cesium] createColoredFlightTrack function not found!');
        }
      ''';
      
      await controller.evaluateJavascript(source: jsCode);
      
      LoggingService.info('Cesium3D: Flight track JavaScript executed');
    } catch (e) {
      LoggingService.error('Cesium3D: Error loading flight track', e);
    }
  }

  void _handleSurfaceError() {
    _surfaceErrorCount++;
    
    if (_surfaceErrorCount > 3 && mounted) {
      LoggingService.warning('Cesium3D Surface: Too many surface errors - recreating WebView');
      
      // Cancel any existing recovery timer
      _surfaceRecoveryTimer?.cancel();
      
      // Schedule WebView recreation
      _surfaceRecoveryTimer = Timer(const Duration(seconds: 1), () {
        if (mounted && !_isDisposed) {
          setState(() {
            _isWebViewReady = false;
          });
          
          // Dispose current WebView
          _disposeWebView();
          
          // Recreate after delay
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && !_isDisposed) {
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
}