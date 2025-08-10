import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../../services/logging_service.dart';

class Cesium3DMapWidget extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;
  final double? initialAltitude;
  
  const Cesium3DMapWidget({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialAltitude,
  });

  @override
  State<Cesium3DMapWidget> createState() => _Cesium3DMapWidgetState();
}

class _Cesium3DMapWidgetState extends State<Cesium3DMapWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() async {
    // Platform-specific setup for Android to enable CORS properly
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is AndroidWebViewPlatform) {
      params = AndroidWebViewControllerCreationParams();
    } else if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    
    _controller = WebViewController.fromPlatformCreationParams(params);
    
    // Android-specific settings for CORS
    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;
      await androidController.setMediaPlaybackRequiresUserGesture(false);
    }
    
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setBackgroundColor(Colors.grey[900]!)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            LoggingService.debug('Cesium3D: Page started loading');
          },
          onPageFinished: (String url) {
            LoggingService.debug('Cesium3D: Page finished loading');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            LoggingService.error('Cesium3D Error', error.description);
          },
          onHttpError: (HttpResponseError error) {
            LoggingService.error('Cesium3D HTTP Error', '${error.response?.statusCode}: ${error.response?.uri}');
          },
        ),
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        LoggingService.debug('Cesium3D JS: ${message.level.name}: ${message.message}');
      })
      // Load from assets with https://appassets.androidplatform.net origin for Android
      ..loadFlutterAsset('assets/cesium_map.html');
  }

  String _buildMinimalCesiumHTML() {
    // Use provided coordinates or default to Switzerland (typical paragliding area)
    final lat = widget.initialLat ?? 46.8182;
    final lon = widget.initialLon ?? 8.2275;
    final altitude = widget.initialAltitude ?? 50000; // 50km altitude for good view
    
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
        }
    </style>
</head>
<body>
    <div id="cesiumContainer"></div>
    
    <script>
        // Your Cesium Ion token
        Cesium.Ion.defaultAccessToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJqdGkiOiIzYzkwM2EwNS00YjU2LTRiMzEtYjE3NC01ODlkYWM3MjMzNmEiLCJpZCI6MzMwMjc0LCJpYXQiOjE3NTQ3MjUxMjd9.IizVx3Z5iR9Xe1TbswK-FKidO9UoWa5pqa4t66NK8W0";
        
        // Simple initialization
        const viewer = new Cesium.Viewer("cesiumContainer", {
            terrain: Cesium.Terrain.fromWorldTerrain(),
        });
        
        console.log('Cesium viewer initialized');
    </script>
</body>
</html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}