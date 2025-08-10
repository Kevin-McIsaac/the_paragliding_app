# Issue #005: Handle Connection Refused Errors

**Priority:** Low  
**Component:** InAppWebView / Development Server  
**Type:** Development Experience  

## Problem Description

Multiple "ERR_CONNECTION_REFUSED" errors appear in logs during development, related to Flutter's hot reload trying to connect to the development server.

## Evidence from Logs

```
15:10:19.110 I flutter : Received error: net::ERR_CONNECTION_REFUSED
15:10:26.801 I flutter : Received error: net::ERR_CONNECTION_REFUSED
15:11:22.519 I flutter : Received error: net::ERR_CONNECTION_REFUSED
15:11:32.259 I flutter : Received error: net::ERR_CONNECTION_REFUSED
15:11:47.493 I flutter : Received error: net::ERR_CONNECTION_REFUSED
15:12:26.950 I flutter : Received error: net::ERR_CONNECTION_REFUSED
```

These errors occur when the WebView tries to connect to Flutter's development server for hot reload functionality.

## Root Cause

1. WebView attempts to connect to Flutter dev server
2. Connection fails because WebView runs in isolated context
3. Error handler logs all connection failures
4. Not a real issue - only affects development

## Proposed Solution

### 1. Filter Development-Only Errors

```dart
// In cesium_3d_map_inappwebview.dart
onReceivedError: (controller, request, error) {
  // Ignore development server connection errors
  if (error.description.contains('ERR_CONNECTION_REFUSED') && 
      kDebugMode && 
      request.url.toString().contains('localhost')) {
    // Skip logging for hot reload attempts
    return;
  }
  
  LoggingService.error('Cesium3D InAppWebView', 
    'Received error: ${error.description}');
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
```

### 2. Add Connection Error Context

```dart
// Provide better error messages
onLoadError: (controller, url, code, message) {
  // Categorize errors
  if (message.contains('ERR_CONNECTION_REFUSED')) {
    if (kDebugMode) {
      // Development server not accessible from WebView
      LoggingService.debug('WebView cannot access Flutter dev server (expected)');
    } else {
      // Production connection issue
      LoggingService.error('Cesium3D', 'Network connection failed: $message');
    }
  } else if (message.contains('ERR_INTERNET_DISCONNECTED')) {
    LoggingService.error('Cesium3D', 'No internet connection available');
  } else {
    LoggingService.error('Cesium3D', 'Load error: $message (code: $code)');
  }
},
```

### 3. Implement Retry Logic for Real Failures

```dart
int _loadRetryCount = 0;
final int _maxRetries = 3;

void _handleLoadError(String url, String error) async {
  // Only retry for actual Cesium resources, not dev server
  if (!error.contains('ERR_CONNECTION_REFUSED') || 
      !url.contains('localhost')) {
    
    if (_loadRetryCount < _maxRetries) {
      _loadRetryCount++;
      LoggingService.info('Retrying Cesium load (attempt $_loadRetryCount)');
      
      // Wait before retry
      await Future.delayed(Duration(seconds: 2 * _loadRetryCount));
      
      // Reload the WebView
      webViewController?.reload();
    } else {
      LoggingService.error('Cesium3D', 
        'Failed to load after $_maxRetries attempts');
      
      // Show error to user
      if (mounted) {
        setState(() {
          _showErrorMessage = true;
        });
      }
    }
  }
}
```

### 4. Add Network Status Detection

```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class _Cesium3DMapInAppWebViewState extends State<Cesium3DMapInAppWebView> {
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  bool _hasInternet = true;
  
  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connectivitySubscription = Connectivity()
      .onConnectivityChanged
      .listen(_updateConnectionStatus);
  }
  
  void _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    _updateConnectionStatus(result);
  }
  
  void _updateConnectionStatus(ConnectivityResult result) {
    setState(() {
      _hasInternet = result != ConnectivityResult.none;
    });
    
    if (!_hasInternet) {
      LoggingService.warning('No internet connection for Cesium');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_hasInternet) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text('No internet connection'),
            Text('Cesium requires internet to load maps'),
          ],
        ),
      );
    }
    
    // Regular WebView build...
  }
}
```

## Implementation Location

File: `/home/kmcisaac/Projects/free_flight_log/free_flight_log_app/lib/presentation/widgets/cesium_3d_map_inappwebview.dart`

Optional dependency: `connectivity_plus` package for network detection

## Testing Requirements

1. Test in debug mode - verify no spam from dev server
2. Test in release mode - verify real errors still logged
3. Test with internet disconnected
4. Test with poor network conditions
5. Verify retry logic works for real failures

## Success Criteria

- [ ] No ERR_CONNECTION_REFUSED logs in development
- [ ] Real network errors properly reported
- [ ] Graceful handling of offline state
- [ ] Retry logic for transient failures
- [ ] Clean console output

## Related Issues

- Issue #004: Clean Console Logging