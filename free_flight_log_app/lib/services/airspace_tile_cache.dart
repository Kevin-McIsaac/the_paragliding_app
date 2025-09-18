import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'logging_service.dart';

/// Simple tile-based cache for airspace API responses
/// Uses zoom level 8 tiles (~150-200km per tile) for efficient caching
class AirspaceTileCache {
  static const int tileZoom = 8; // 65,536 tiles globally (256x256)
  static const Duration cacheDuration = Duration(hours: 24);
  static const int maxCacheSize = 20000; // Maximum tiles to cache (~250MB memory)

  // Cache structure: tileKey → (timestamp, GeoJSON response)
  final Map<String, (DateTime timestamp, String response)> _tileCache = {};

  // Cache metrics for monitoring
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalRequests = 0;

  /// Convert lat/lng to tile coordinates at tileZoom level
  (int x, int y) _toTileCoords(double lat, double lng) {
    final n = math.pow(2, tileZoom).toDouble();
    final x = ((lng + 180) / 360 * n).floor();
    final latRad = lat * math.pi / 180;
    final y = ((1 - math.log(math.tan(latRad) + 1/math.cos(latRad)) / math.pi) / 2 * n).floor();
    return (x.clamp(0, n.toInt() - 1), y.clamp(0, n.toInt() - 1));
  }

  /// Get bounding box for a tile
  fm.LatLngBounds _tileToBounds(int x, int y) {
    final n = math.pow(2, tileZoom).toDouble();
    final west = x / n * 360 - 180;
    final east = (x + 1) / n * 360 - 180;
    final north = math.atan(_sinh(math.pi * (1 - 2 * y / n))) * 180 / math.pi;
    final south = math.atan(_sinh(math.pi * (1 - 2 * (y + 1) / n))) * 180 / math.pi;
    return fm.LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  /// Calculate hyperbolic sine (sinh)
  double _sinh(double x) {
    return (math.exp(x) - math.exp(-x)) / 2;
  }

  /// Get all tiles that intersect with the given viewport
  List<(int x, int y)> _getTilesForViewport(fm.LatLngBounds viewport) {
    final tiles = <(int, int)>{};

    // Get corner tiles
    final sw = _toTileCoords(viewport.south, viewport.west);
    final ne = _toTileCoords(viewport.north, viewport.east);

    // Add all tiles in the rectangle
    for (int x = sw.$1; x <= ne.$1; x++) {
      for (int y = ne.$2; y <= sw.$2; y++) {
        tiles.add((x, y));
      }
    }

    return tiles.toList();
  }

  /// Generate a unique key for a tile
  String _tileKey(int x, int y) => '${tileZoom}_${x}_$y';

  /// Check if cached data is still valid
  bool _isCacheValid(DateTime timestamp) {
    return DateTime.now().difference(timestamp) < cacheDuration;
  }

  /// Evict oldest cache entries if cache is too large
  void _evictOldestIfNeeded() {
    if (_tileCache.length <= maxCacheSize) return;

    // Find and remove oldest entry
    String? oldestKey;
    DateTime? oldestTime;

    for (final entry in _tileCache.entries) {
      if (oldestTime == null || entry.value.$1.isBefore(oldestTime)) {
        oldestTime = entry.value.$1;
        oldestKey = entry.key;
      }
    }

    if (oldestKey != null) {
      _tileCache.remove(oldestKey);
      // Removed verbose eviction logging
    }
  }

  /// Get cached response for a specific tile if available and valid
  String? getCachedTile(int x, int y) {
    final key = _tileKey(x, y);
    final cached = _tileCache[key];

    if (cached != null && _isCacheValid(cached.$1)) {
      return cached.$2;
    }

    return null;
  }

  /// Store a tile response in cache
  void cacheTile(int x, int y, String response) {
    _evictOldestIfNeeded();
    final key = _tileKey(x, y);
    _tileCache[key] = (DateTime.now(), response);
  }

  /// Get tiles needed for viewport, returning cached and uncached tiles separately
  ({
    List<String> cachedResponses,
    List<(int x, int y)> tilesToFetch,
    fm.LatLngBounds Function(int, int) tileToBounds,
  }) getTilesForViewport(fm.LatLngBounds viewport) {
    _totalRequests++;

    final tiles = _getTilesForViewport(viewport);
    final cachedResponses = <String>[];
    final tilesToFetch = <(int, int)>[];

    // Only log significant cache requests (large viewports or periodic)
    if (tiles.length > 20 || _totalRequests % 5 == 1) {
      LoggingService.structured('TILE_CACHE_REQUEST', {
        'viewport_tiles': tiles.length,
        'cache_size': _tileCache.length,
        'viewport': '${viewport.west.toStringAsFixed(2)},${viewport.south.toStringAsFixed(2)},${viewport.east.toStringAsFixed(2)},${viewport.north.toStringAsFixed(2)}',
      });
    }

    for (final tile in tiles) {
      final cached = getCachedTile(tile.$1, tile.$2);
      if (cached != null) {
        cachedResponses.add(cached);
        _cacheHits++;
      } else {
        tilesToFetch.add(tile);
        _cacheMisses++;
      }
    }

    // Log cache performance metrics
    if (_totalRequests % 10 == 0) {  // Log every 10 requests
      final hitRate = _cacheHits > 0 ? (_cacheHits * 100.0 / (_cacheHits + _cacheMisses)).toStringAsFixed(1) : '0.0';
      LoggingService.structured('TILE_CACHE_METRICS', {
        'total_requests': _totalRequests,
        'cache_hits': _cacheHits,
        'cache_misses': _cacheMisses,
        'hit_rate_percent': hitRate,
        'cache_size': _tileCache.length,
        'max_cache_size': maxCacheSize,
      });
    }

    // Log summary when there are tiles to fetch or it's a large operation
    if (tilesToFetch.isNotEmpty || tiles.length > 20) {
      LoggingService.info('[TILE_CACHE] Tiles: ${tiles.length} total, ${cachedResponses.length} cached, ${tilesToFetch.length} to fetch');
    }

    return (
      cachedResponses: cachedResponses,
      tilesToFetch: tilesToFetch,
      tileToBounds: _tileToBounds,
    );
  }

  /// Merge multiple GeoJSON FeatureCollection responses into one
  String mergeGeoJsonResponses(List<String> responses) {
    if (responses.isEmpty) {
      return '{"type":"FeatureCollection","features":[]}';
    }

    if (responses.length == 1) {
      return responses.first;
    }

    try {
      final features = <Map<String, dynamic>>[];
      final seenSignatures = <String>{};

      for (final response in responses) {
        final json = jsonDecode(response) as Map<String, dynamic>;
        if (json['type'] == 'FeatureCollection' && json['features'] != null) {
          for (final feature in json['features'] as List) {
            final featureMap = feature as Map<String, dynamic>;

            // Create a unique signature based on properties to avoid duplicates
            // Use _id if available, otherwise create signature from name + type + coordinates
            String signature;
            if (featureMap['_id'] != null) {
              signature = featureMap['_id'].toString();
            } else if (featureMap['properties'] != null) {
              final props = featureMap['properties'];
              // Create signature from name, type, and first coordinate
              final name = props['name'] ?? '';
              final type = props['type'] ?? '';
              final coords = featureMap['geometry']?['coordinates'];
              final firstCoord = coords != null && coords is List && coords.isNotEmpty
                  ? coords[0].toString()
                  : '';
              signature = '$name|$type|$firstCoord';
            } else {
              // If no identifying info, include all features (may have duplicates)
              features.add(featureMap);
              continue;
            }

            if (!seenSignatures.contains(signature)) {
              seenSignatures.add(signature);
              features.add(featureMap);
            }
          }
        }
      }

      // Only log merging for large operations
      if (responses.length > 10 || features.length > 100) {
        LoggingService.debug('[TILE_CACHE] Merged ${responses.length} responses into ${features.length} unique features');
      }

      return jsonEncode({
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (e, stackTrace) {
      LoggingService.error('[TILE_CACHE] Error merging GeoJSON responses', e, stackTrace);
      return responses.first; // Fallback to first response
    }
  }

  /// Clear the entire cache
  void clearCache() {
    _tileCache.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
    _totalRequests = 0;
    LoggingService.info('[TILE_CACHE] Cache cleared');
  }

  /// Get current cache statistics
  Map<String, dynamic> getCacheStats() {
    final hitRate = (_cacheHits + _cacheMisses) > 0
        ? (_cacheHits * 100.0 / (_cacheHits + _cacheMisses))
        : 0.0;

    return {
      'cache_size': _tileCache.length,
      'max_size': maxCacheSize,
      'total_requests': _totalRequests,
      'cache_hits': _cacheHits,
      'cache_misses': _cacheMisses,
      'hit_rate_percent': hitRate.toStringAsFixed(1),
      'cache_duration_hours': cacheDuration.inHours,
      'tile_zoom_level': tileZoom,
    };
  }
}