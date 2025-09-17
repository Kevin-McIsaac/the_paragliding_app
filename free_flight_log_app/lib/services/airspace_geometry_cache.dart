import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:latlong2/latlong.dart';
import '../services/logging_service.dart';
import '../services/airspace_disk_cache.dart';
import '../data/models/airspace_cache_models.dart';

/// Manages deduplicated airspace geometry storage
class AirspaceGeometryCache {
  static AirspaceGeometryCache? _instance;
  final AirspaceDiskCache _diskCache = AirspaceDiskCache.instance;

  // In-memory LRU cache for frequently accessed geometries
  final Map<String, CachedAirspaceGeometry> _memoryCache = {};
  final List<String> _accessOrder = [];
  static const int _maxMemoryCacheSize = 50; // Keep 50 most recent geometries

  // Statistics tracking
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _diskHits = 0;
  final Map<String, int> _duplicateCount = {};

  AirspaceGeometryCache._internal();

  static AirspaceGeometryCache get instance {
    _instance ??= AirspaceGeometryCache._internal();
    return _instance!;
  }

  /// Generate a unique ID for an airspace
  String generateAirspaceId(Map<String, dynamic> feature) {
    // Try to use OpenAIP _id first
    if (feature['_id'] != null) {
      return feature['_id'].toString();
    }

    // Fallback: generate hash from stable properties
    final properties = feature['properties'] ?? {};
    final name = properties['name'] ?? 'unknown';
    final type = properties['type'] ?? 'unknown';
    final country = properties['country'] ?? '';

    final idString = '$name|$type|$country';
    final bytes = utf8.encode(idString);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  /// Generate a hash of geometry for change detection
  String generateGeometryHash(List<List<LatLng>> polygons) {
    final coords = polygons.expand((polygon) {
      return polygon.map((point) => '${point.latitude},${point.longitude}');
    }).join('|');

    final bytes = utf8.encode(coords);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Store an airspace geometry
  Future<void> putGeometry(Map<String, dynamic> feature) async {
    final stopwatch = Stopwatch()..start();

    try {
      final id = generateAirspaceId(feature);
      final properties = feature['properties'] ?? {};
      final geometry = feature['geometry'] ?? {};

      // Parse polygons from GeoJSON
      final polygons = _parsePolygons(geometry);
      if (polygons.isEmpty) {
        LoggingService.debug('Skipping airspace with no valid polygons: $id');
        return;
      }

      final geometryHash = generateGeometryHash(polygons);

      // Check if geometry already exists and is unchanged
      final existing = await getGeometry(id);
      if (existing != null && existing.geometryHash == geometryHash) {
        LoggingService.debug('Geometry unchanged, skipping update: $id');
        _trackDuplicate(id);
        return;
      }

      // Create cached geometry object
      final cachedGeometry = CachedAirspaceGeometry(
        id: id,
        name: properties['name'] ?? 'Unknown',
        type: properties['type'] ?? 'Unknown',
        polygons: polygons,
        properties: properties,
        fetchTime: DateTime.now(),
        geometryHash: geometryHash,
      );

      // Store to disk
      await _diskCache.putGeometry(cachedGeometry);

      // Update memory cache
      _updateMemoryCache(id, cachedGeometry);

      LoggingService.performance(
        'Stored airspace geometry',
        stopwatch.elapsed,
        'id=$id, polygons=${polygons.length}',
      );
    } catch (e, stack) {
      LoggingService.error('Failed to store geometry', e, stack);
    }
  }

  /// Retrieve an airspace geometry by ID
  Future<CachedAirspaceGeometry?> getGeometry(String id) async {
    // Check memory cache first
    if (_memoryCache.containsKey(id)) {
      _cacheHits++;
      _updateAccessOrder(id);
      LoggingService.debug('Memory cache hit for geometry: $id');
      return _memoryCache[id];
    }

    // Check disk cache
    _cacheMisses++;
    final geometry = await _diskCache.getGeometry(id);

    if (geometry != null) {
      _diskHits++;
      _updateMemoryCache(id, geometry);
      LoggingService.debug('Disk cache hit for geometry: $id');
      return geometry;
    }

    LoggingService.debug('Cache miss for geometry: $id');
    return null;
  }

  /// Retrieve multiple geometries by IDs
  Future<List<CachedAirspaceGeometry>> getGeometries(Set<String> ids) async {
    if (ids.isEmpty) return [];

    final stopwatch = Stopwatch()..start();
    final geometries = <CachedAirspaceGeometry>[];
    final missingIds = <String>{};

    // Check memory cache first
    for (final id in ids) {
      if (_memoryCache.containsKey(id)) {
        geometries.add(_memoryCache[id]!);
        _updateAccessOrder(id);
        _cacheHits++;
      } else {
        missingIds.add(id);
        _cacheMisses++;
      }
    }

    // Fetch missing from disk
    if (missingIds.isNotEmpty) {
      final diskGeometries = await _diskCache.getGeometries(missingIds);
      for (final geometry in diskGeometries) {
        geometries.add(geometry);
        _updateMemoryCache(geometry.id, geometry);
        _diskHits++;
      }
    }

    LoggingService.performance(
      'Retrieved multiple geometries',
      stopwatch.elapsed,
      'requested=${ids.length}, memory=${ids.length - missingIds.length}, disk=${geometries.length - (ids.length - missingIds.length)}',
    );

    return geometries;
  }

  /// Parse polygons from GeoJSON geometry
  List<List<LatLng>> _parsePolygons(Map<String, dynamic> geometry) {
    final type = geometry['type'] as String?;
    final coordinates = geometry['coordinates'];

    if (coordinates == null || coordinates is! List) {
      return [];
    }

    final polygons = <List<LatLng>>[];

    if (type == 'Polygon') {
      for (final ring in coordinates) {
        if (ring is List) {
          final points = <LatLng>[];
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              points.add(LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ));
            }
          }
          if (points.isNotEmpty) {
            polygons.add(points);
          }
        }
      }
    } else if (type == 'MultiPolygon') {
      for (final polygon in coordinates) {
        if (polygon is List && polygon.isNotEmpty) {
          final ring = polygon[0]; // Only use outer ring for now
          if (ring is List) {
            final points = <LatLng>[];
            for (final coord in ring) {
              if (coord is List && coord.length >= 2) {
                points.add(LatLng(
                  (coord[1] as num).toDouble(),
                  (coord[0] as num).toDouble(),
                ));
              }
            }
            if (points.isNotEmpty) {
              polygons.add(points);
            }
          }
        }
      }
    }

    return polygons;
  }

  /// Update memory cache with LRU eviction
  void _updateMemoryCache(String id, CachedAirspaceGeometry geometry) {
    // Remove from current position if exists
    _accessOrder.remove(id);

    // Add to front
    _accessOrder.insert(0, id);
    _memoryCache[id] = geometry;

    // Evict if over limit
    while (_accessOrder.length > _maxMemoryCacheSize) {
      final evictId = _accessOrder.removeLast();
      _memoryCache.remove(evictId);
      LoggingService.debug('Evicted geometry from memory: $evictId');
    }
  }

  /// Update access order for LRU
  void _updateAccessOrder(String id) {
    _accessOrder.remove(id);
    _accessOrder.insert(0, id);
  }

  /// Track duplicate airspace references
  void _trackDuplicate(String id) {
    _duplicateCount[id] = (_duplicateCount[id] ?? 0) + 1;
  }

  /// Get cache statistics
  CacheStatistics getStatistics() {
    final hitRate = (_cacheHits + _cacheMisses) > 0
        ? _cacheHits / (_cacheHits + _cacheMisses)
        : 0.0;

    final totalDuplicates = _duplicateCount.values.fold(0, (sum, count) => sum + count);

    // Calculate memory usage
    var memoryBytes = 0;
    for (final geometry in _memoryCache.values) {
      // Rough estimate: 100 bytes per point
      final pointCount = geometry.polygons.fold(0, (sum, polygon) => sum + polygon.length);
      memoryBytes += pointCount * 100;
    }

    return CacheStatistics(
      totalGeometries: _memoryCache.length,
      totalTiles: 0, // Will be set by metadata cache
      emptyTiles: 0, // Will be set by metadata cache
      duplicatedAirspaces: totalDuplicates,
      totalMemoryBytes: memoryBytes,
      compressedBytes: 0, // Will be set by disk cache
      averageCompressionRatio: 0, // Will be set by disk cache
      cacheHitRate: hitRate,
      lastUpdated: DateTime.now(),
    );
  }

  /// Clear memory cache
  void clearMemoryCache() {
    _memoryCache.clear();
    _accessOrder.clear();
    _cacheHits = 0;
    _cacheMisses = 0;
    _diskHits = 0;
    _duplicateCount.clear();
    LoggingService.info('Cleared airspace geometry memory cache');
  }

  /// Clear all cache (memory and disk)
  Future<void> clearAllCache() async {
    clearMemoryCache();
    await _diskCache.clearCache();
    LoggingService.info('Cleared all airspace geometry cache');
  }

  /// Clean expired data
  Future<void> cleanExpiredData() async {
    await _diskCache.cleanExpiredData();

    // Remove expired items from memory cache
    final now = DateTime.now();
    final expiredIds = <String>[];

    for (final entry in _memoryCache.entries) {
      if (entry.value.isExpired) {
        expiredIds.add(entry.key);
      }
    }

    for (final id in expiredIds) {
      _memoryCache.remove(id);
      _accessOrder.remove(id);
    }

    if (expiredIds.isNotEmpty) {
      LoggingService.info('Removed ${expiredIds.length} expired geometries from memory cache');
    }
  }

  /// Get cache performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'memoryHits': _cacheHits,
      'memoryMisses': _cacheMisses,
      'diskHits': _diskHits,
      'hitRate': (_cacheHits + _cacheMisses) > 0
          ? (_cacheHits / (_cacheHits + _cacheMisses) * 100).toStringAsFixed(1)
          : '0.0',
      'memoryCacheSize': _memoryCache.length,
      'duplicatesDetected': _duplicateCount.length,
      'totalDuplicateReferences': _duplicateCount.values.fold(0, (sum, count) => sum + count),
    };
  }
}