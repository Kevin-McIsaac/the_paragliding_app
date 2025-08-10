import 'dart:async';
import 'dart:convert';
import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../services/logging_service.dart';
import '../../config/cesium_config.dart';
import 'cesium/cesium_webview_controller.dart';
import 'cesium/cesium_memory_manager.dart';
import 'cesium/cesium_connectivity_manager.dart';

/// Refactored Cesium 3D Map Widget using InAppWebView
/// 
/// This widget displays a 3D globe using CesiumJS with improved architecture:
/// - Separated concerns into dedicated manager classes
/// - Better memory management
/// - Improved error handling
/// - Cleaner code structure
class Cesium3DMapRefactored extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final double? initialAltitude;
  
  const Cesium3DMapRefactored({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialAltitude,
  });

  @override
  State<Cesium3DMapRefactored> createState() => _Cesium3DMapRefactoredState();
}

class _Cesium3DMapRefactoredState extends State<Cesium3DMapRefactored> 
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  
  // Managers
  late final CesiumWebViewController _webViewController;
  late final CesiumMemoryManager _memoryManager;
  late final CesiumConnectivityManager _connectivityManager;
  
  // State
  bool _isLoading = true;
  bool _isDisposed = false;
  bool _hasInternet = true;
  bool _showErrorMessage = false;
  String _errorMessage = '';
  String? _cesiumHtml;
  bool _htmlLoadError = false;
  
  // Retry logic
  int _loadRetryCount = 0;
  final int _maxRetries = 3;
  
  // Cancellation tokens
  CancelableOperation<void>? _htmlLoadOperation;
  
  // Keep widget alive to prevent surface recreation
  @override
  bool get wantKeepAlive => true;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize managers
    _webViewController = CesiumWebViewController();
    _memoryManager = CesiumMemoryManager(_webViewController);
    _connectivityManager = CesiumConnectivityManager(
      onConnectivityChanged: _onConnectivityChanged,
    );
    
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Start initialization
    _initialize();
  }
  
  /// Initializes the widget
  void _initialize() {
    // Load HTML template
    _htmlLoadOperation = CancelableOperation.fromFuture(_loadCesiumHtml());
    
    // Start connectivity monitoring
    _connectivityManager.startMonitoring();
    
    // Start memory monitoring (delayed to avoid startup overhead)
    if (kDebugMode) {
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isDisposed) {
          _memoryManager.startMonitoring();
        }
      });
    }
  }
  
  /// Loads Cesium HTML from assets
  Future<void> _loadCesiumHtml() async {
    try {
      if (_isDisposed) return;
      
      // Load HTML template and JavaScript from assets
      final htmlTemplate = await rootBundle.loadString('assets/cesium/cesium.html');
      
      if (_isDisposed) return;
      
      final jsContent = await rootBundle.loadString('assets/cesium/cesium.js');
      
      if (_isDisposed) return;
      
      // Inject JavaScript content into HTML template
      final htmlWithJs = htmlTemplate.replaceAll('{{JS_CONTENT}}', jsContent);
      
      // Store the loaded HTML for use
      if (mounted && !_isDisposed) {
        setState(() {
          _cesiumHtml = htmlWithJs;
        });
      }
      
      LoggingService.debug('Cesium3DMapRefactored: Loaded HTML and JS assets successfully');
    } catch (e) {
      if (_isDisposed) return;
      
      LoggingService.error('Cesium3DMapRefactored', 'Failed to load HTML assets: $e');
      if (mounted && !_isDisposed) {
        setState(() {
          _htmlLoadError = true;
        });
      }
    }
  }
  
  /// Builds the Cesium HTML with parameters
  String _buildCesiumHtml() {
    final lat = widget.initialLat ?? 46.8182;
    final lon = widget.initialLon ?? 8.2275;
    final altitude = widget.initialAltitude ?? 2000000;
    final bool isDebugMode = kDebugMode;
    
    if (_cesiumHtml != null) {
      return _cesiumHtml!
        .replaceAll('{{LAT}}', lat.toString())
        .replaceAll('{{LON}}', lon.toString())
        .replaceAll('{{ALTITUDE}}', altitude.toString())
        .replaceAll('{{DEBUG}}', isDebugMode.toString())
        .replaceAll('{{TOKEN}}', CesiumConfig.ionAccessToken);
    }
    
    // This shouldn't happen if HTML loaded successfully
    return '<html><body>Error loading map</body></html>';
  }
  
  /// Handles connectivity changes
  void _onConnectivityChanged(bool hasInternet) {
    if (mounted && !_isDisposed) {
      setState(() {
        _hasInternet = hasInternet;
      });
      
      // Reload if we regained connection and had an error
      if (hasInternet && _showErrorMessage) {
        _retryLoad();
      }
    }
  }
  
  /// Handles WebView creation
  void _onWebViewCreated(InAppWebViewController controller) {
    if (!_isDisposed) {
      _webViewController.setController(controller);
      LoggingService.debug('Cesium3DMapRefactored: WebView created');
    }
  }
  
  /// Handles WebView load completion
  void _onLoadStop(InAppWebViewController controller, WebUri? url) async {
    if (!_isDisposed) {
      LoggingService.debug('Cesium3DMapRefactored: Load complete');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadRetryCount = 0;
        });
      }
    }
  }
  
  /// Handles WebView console messages
  void _onConsoleMessage(InAppWebViewController controller, ConsoleMessage consoleMessage) {
    if (!kDebugMode && consoleMessage.messageLevel != ConsoleMessageLevel.ERROR) {
      return;
    }
    
    final msg = consoleMessage.message;
    if (msg.contains('Tiles queued') || 
        msg.contains('Memory:') || 
        msg.contains('Debug')) {
      return;
    }
    
    final level = consoleMessage.messageLevel == ConsoleMessageLevel.ERROR ? 'ERROR' :
                 consoleMessage.messageLevel == ConsoleMessageLevel.WARNING ? 'WARNING' :
                 consoleMessage.messageLevel == ConsoleMessageLevel.LOG ? 'LOG' : 'DEBUG';
    
    if (consoleMessage.messageLevel == ConsoleMessageLevel.ERROR) {
      LoggingService.error('Cesium3D JS', msg);
    } else if (kDebugMode) {
      LoggingService.debug('Cesium3D JS [$level]: $msg');
    }
  }
  
  /// Handles WebView load errors
  void _onLoadError(InAppWebViewController controller, WebUri? url, int code, String message) {
    if (message.contains('ERR_CONNECTION_REFUSED')) {
      if (kDebugMode && url.toString().contains('localhost')) {
        LoggingService.debug('WebView cannot access Flutter dev server (expected)');
      } else {
        LoggingService.error('Cesium3DMapRefactored', 'Network connection failed: $message');
        _handleLoadError(url.toString(), message);
      }
    } else if (message.contains('ERR_INTERNET_DISCONNECTED')) {
      LoggingService.error('Cesium3DMapRefactored', 'No internet connection available');
      _handleNoInternet();
    } else {
      LoggingService.error('Cesium3DMapRefactored', 'Load error: $message (code: $code)');
      _handleLoadError(url.toString(), message);
    }
  }
  
  /// Handles load errors with retry logic
  Future<void> _handleLoadError(String url, String error) async {
    if (!error.contains('ERR_CONNECTION_REFUSED') || !url.contains('localhost')) {
      if (_loadRetryCount < _maxRetries && !_isDisposed) {
        _loadRetryCount++;
        LoggingService.info('Retrying Cesium load (attempt $_loadRetryCount/$_maxRetries)');
        
        await Future.delayed(Duration(seconds: 2 * _loadRetryCount));
        
        if (_isDisposed) return;
        
        if (mounted && !_isDisposed) {
          await _webViewController.reload();
        }
      } else if (!_isDisposed) {
        LoggingService.error('Cesium3DMapRefactored', 
          'Failed to load after $_maxRetries attempts');
        
        if (mounted && !_isDisposed) {
          setState(() {
            _showErrorMessage = true;
            _errorMessage = 'Unable to load the 3D map after $_maxRetries attempts.\nPlease check your internet connection.';
          });
        }
      }
    }
  }
  
  /// Handles no internet connection
  void _handleNoInternet() {
    if (mounted) {
      setState(() {
        _showErrorMessage = true;
        _errorMessage = 'No internet connection available.\nThe 3D map requires an active internet connection.';
      });
    }
  }
  
  /// Retries loading the WebView
  void _retryLoad() {
    setState(() {
      _showErrorMessage = false;
      _errorMessage = '';
      _loadRetryCount = 0;
      _isLoading = true;
    });
    _webViewController.reload();
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    // Show offline message if no internet
    if (!_hasInternet) {
      return _buildNoInternetWidget();
    }
    
    // Show loading while HTML is being loaded from assets
    if (_cesiumHtml == null && !_htmlLoadError) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    // Show error if HTML failed to load
    if (_htmlLoadError) {
      return _buildLoadErrorWidget();
    }
    
    // Main WebView
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
            allowUniversalAccessFromFileURLs: true,  // Key for CORS bypass
            // Memory optimization settings
            cacheMode: CacheMode.LOAD_NO_CACHE,
            domStorageEnabled: false,
            databaseEnabled: false,
            clearSessionCache: true,
            // Performance settings
            thirdPartyCookiesEnabled: false,
            allowContentAccess: true,
            // Surface handling settings
            useHybridComposition: true,
            hardwareAcceleration: true,
            supportMultipleWindows: false,
            useWideViewPort: false,
            // iOS-specific settings
            allowsInlineMediaPlayback: true,
            allowsAirPlayForMediaPlayback: false,
          ),
          onWebViewCreated: _onWebViewCreated,
          onLoadStop: _onLoadStop,
          onConsoleMessage: _onConsoleMessage,
          onLoadError: _onLoadError,
          onReceivedError: (controller, request, error) {
            final errorDesc = error.description ?? '';
            final urlString = request.url?.toString() ?? '';
            
            if (errorDesc.contains('ERR_CONNECTION_REFUSED')) {
              if (kDebugMode && (urlString.contains('localhost') || urlString.contains('127.0.0.1'))) {
                return;
              }
              LoggingService.error('Cesium3DMapRefactored', 'Connection refused: $urlString');
            } else if (!errorDesc.contains('ERR_INTERNET_DISCONNECTED')) {
              LoggingService.error('Cesium3DMapRefactored', 'Received error: $errorDesc');
            }
          },
        ),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
        if (_showErrorMessage)
          _buildErrorOverlay(),
      ],
    );
  }
  
  /// Builds the no internet widget
  Widget _buildNoInternetWidget() {
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
              onPressed: () => _connectivityManager.checkConnectivity(),
              icon: const Icon(Icons.refresh),
              label: const Text('Check Connection'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Builds the load error widget
  Widget _buildLoadErrorWidget() {
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
  
  /// Builds the error overlay
  Widget _buildErrorOverlay() {
    return Center(
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
    );
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_isDisposed) return;
    
    if (kDebugMode) {
      LoggingService.debug('Cesium3DMapRefactored: App lifecycle - $state');
    }
    
    switch (state) {
      case AppLifecycleState.paused:
        _memoryManager.handleAppPause();
        break;
      case AppLifecycleState.resumed:
        _memoryManager.handleAppResume();
        break;
      case AppLifecycleState.detached:
        _dispose();
        break;
      default:
        break;
    }
  }
  
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    
    if (_isDisposed) return;
    
    _memoryManager.handleMemoryWarning();
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    
    // Cancel operations
    _htmlLoadOperation?.cancel();
    
    // Dispose managers
    _memoryManager.dispose();
    _connectivityManager.dispose();
    _webViewController.dispose();
    
    // Remove observer
    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
  }
  
  void _dispose() async {
    await _webViewController.dispose();
  }
}