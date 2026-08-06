import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/logging_service.dart';

/// Unified tile provider for all Flutter Map instances in the app.
///
/// Every map screen (nearby sites, edit site, flight track) goes through
/// [createInstance], so they all share one [BuiltInMapCachingProvider] -
/// flutter_map's disk-backed tile cache, persisted at
/// `<ApplicationCacheDirectory>/fm_cache` and surviving app restarts. That
/// provider is a process-wide singleton that only respects configuration
/// (like [maxCacheSizeBytes]) the first time it's created, so it's
/// configured explicitly here rather than left to whichever screen happens
/// to load a tile first. See `CacheUtils` for inspecting/clearing it.
class MapTileProvider {
  /// Cap for the shared on-disk tile cache. 300 MB comfortably covers a
  /// season of OSM/satellite tiles across all map screens without letting
  /// an unbounded cache eat into a phone's storage.
  static const int maxCacheSizeBytes = 300 * 1024 * 1024;

  static Map<String, String> get _standardHeaders => {
    'User-Agent': 'TheParaglidingApp/1.0',
  };

  static BuiltInMapCachingProvider get cachingProvider =>
      BuiltInMapCachingProvider.getOrCreateInstance(
        maxCacheSize: maxCacheSizeBytes,
      );

  /// Create a new tile provider instance.
  /// Returns debug provider in debug mode, standard provider in release.
  /// Each instance shares the same on-disk cache (see class doc).
  static TileProvider createInstance() {
    return kDebugMode
        ? _DebugNetworkTileProvider(headers: _standardHeaders, cachingProvider: cachingProvider)
        : NetworkTileProvider(headers: _standardHeaders, cachingProvider: cachingProvider);
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
  _DebugNetworkTileProvider({super.headers, super.cachingProvider});
  
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    LoggingService.debug('Network tile request: z${coordinates.z}/${coordinates.x}/${coordinates.y}');
    return super.getImage(coordinates, options);
  }
}