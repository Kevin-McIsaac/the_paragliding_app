import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/logging_service.dart';

/// Unified tile provider for all Flutter Map instances in the app.
/// Provides consistent caching and debug logging across all map screens.
class MapTileProvider {
  /// Standard headers for all tile requests with reasonable caching
  static Map<String, String> get _standardHeaders => {
    'User-Agent': 'FreeFlightLog/1.0',
    'Cache-Control': 'max-age=86400', // 24 hours cache
  };
  
  /// Create a new tile provider instance.
  /// Returns debug provider in debug mode, standard provider in release.
  /// Each instance shares the same caching via Flutter Map's internal cache.
  static TileProvider createInstance() {
    return kDebugMode 
        ? _DebugNetworkTileProvider(headers: _standardHeaders)
        : NetworkTileProvider(headers: _standardHeaders);
  }
  
  /// Get error callback for debug mode tile error logging
  static void Function(TileImage tile, Object error, StackTrace? stackTrace)? getErrorCallback() {
    return kDebugMode ? (tile, error, stackTrace) {
      LoggingService.debug('Tile error: ${tile.coordinates} - $error');
    } : null;
  }
}

/// Debug tile provider that logs network requests for development
class _DebugNetworkTileProvider extends NetworkTileProvider {
  _DebugNetworkTileProvider({super.headers});
  
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    LoggingService.debug('Network tile request: z${coordinates.z}/${coordinates.x}/${coordinates.y}');
    return super.getImage(coordinates, options);
  }
}