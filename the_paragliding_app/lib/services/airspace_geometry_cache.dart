import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:latlong2/latlong.dart';
import '../services/logging_service.dart';
import '../services/airspace_disk_cache.dart';
import '../services/airspace_geojson_service.dart' show ClipperData;
import '../data/models/airspace_cache_models.dart';
import '../utils/performance_monitor.dart';

/// Manages deduplicated airspace geometry storage with memory cache
class AirspaceGeometryCache {
  static AirspaceGeometryCache? _instance;
  final AirspaceDiskCache _diskCache = AirspaceDiskCache.instance;

  // In-memory LRU cache for fast access
  final Map<String, CachedAirspaceGeometry> _memoryCache = {};
  final List<String> _accessOrder = [];
  static const int _maxMemoryCacheSize = 50000; // Cache up to 50000 geometries in memory (optimized based on actual usage)

  // Statistics tracking
  int _memoryHits = 0;
  int _memoryMisses = 0;
  int _diskHits = 0;
  int _diskMisses = 0;
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

      // The OpenAIP API returns features with properties at the top level, not in a 'properties' field
      // Check if properties is a separate field (standard GeoJSON) or if properties are at top level (OpenAIP format)
      final rawProperties = feature['properties'];
      final rawGeometry = feature['geometry'];

      Map<String, dynamic> properties;
      if (rawProperties != null && rawProperties is Map) {
        // Standard GeoJSON format with properties field
        properties = Map<String, dynamic>.from(rawProperties);
      } else {
        // OpenAIP format - extract all fields except geometry as properties
        properties = <String, dynamic>{};
        for (final key in feature.keys) {
          if (key != 'geometry') {
            properties[key] = feature[key];
          }
        }
      }

      final geometry = rawGeometry is Map ? Map<String, dynamic>.from(rawGeometry) : <String, dynamic>{};

      // Parse polygons from GeoJSON
      final polygons = _parsePolygons(geometry);
      if (polygons.isEmpty) {
        return;
      }

      final geometryHash = generateGeometryHash(polygons);

      // Check if geometry already exists and is unchanged
      final existing = await getGeometry(id);
      if (existing != null && existing.geometryHash == geometryHash) {
        _trackDuplicate(id);
        return;
      }

      // Create cached geometry object
      // Extract numeric type code - ensure it's stored as int
      final typeCode = properties['type'] is int
          ? properties['type'] as int
          : (properties['type'] as num?)?.toInt() ?? 0;

      // Convert LatLng polygons to ClipperData for optimal performance
      final clipperData = ClipperData.fromLatLngPolygons(polygons);

      final cachedGeometry = CachedAirspaceGeometry(
        id: id,
        name: properties['name'] ?? 'Unknown',
        typeCode: typeCode,  // Store numeric type code
        clipperData: clipperData,
        properties: properties,
        fetchTime: DateTime.now(),
        geometryHash: geometryHash,
      );

      // Store to disk only
      await _diskCache.putGeometry(cachedGeometry);

      // Only log slow operations or errors
      if (stopwatch.elapsedMilliseconds > 50) {
        LoggingService.performance(
          'Stored airspace geometry',
          stopwatch.elapsed,
          'id=$id, polygons=${polygons.length}, name=${cachedGeometry.name}, typeCode=${cachedGeometry.typeCode}',
        );
      }
    } catch (e, stack) {
      LoggingService.error('Failed to store geometry', e, stack);
    }
  }

  /// Batch store multiple geometries efficiently
  Future<void> putGeometryBatch(List<Map<String, dynamic>> features) async {
    final stopwatch = Stopwatch()..start();
    var newGeometries = 0;
    var duplicates = 0;

    // Collect all unique IDs to check
    final Map<String, Map<String, dynamic>> featureMap = {};
    final Set<String> idsToCheck = {};

    for (final feature in features) {
      try {
        final id = generateAirspaceId(feature);
        idsToCheck.add(id);
        featureMap[id] = feature;
      } catch (e, stack) {
        LoggingService.error('Failed to generate ID for feature', e, stack);
      }
    }

    // Batch check existing geometries (single disk query)
    final existingIds = await _diskCache.getExistingIds(idsToCheck.toList());

    // Collect all new geometries to insert in batch
    final List<CachedAirspaceGeometry> geometriesToInsert = [];

    // Process only new geometries
    for (final entry in featureMap.entries) {
      final id = entry.key;
      final feature = entry.value;

      if (!existingIds.contains(id)) {
        // New geometry - process it
        final geometry = _processGeometry(id, feature);
        if (geometry != null) {
          geometriesToInsert.add(geometry);
          newGeometries++;
        }
      } else {
        duplicates++;
        _trackDuplicate(id);
      }
    }

    // Batch insert all new geometries at once
    if (geometriesToInsert.isNotEmpty) {
      await _diskCache.putGeometryBatch(geometriesToInsert);
    }

    LoggingService.debug(
      'Processed ${features.length} features: $newGeometries new, $duplicates duplicates (${stopwatch.elapsedMilliseconds}ms)'
    );
  }

  /// Helper method to process a geometry without storing it
  CachedAirspaceGeometry? _processGeometry(String id, Map<String, dynamic> feature) {
    try {
      // Extract properties and geometry (handle both formats)
      final rawProperties = feature['properties'];
      final rawGeometry = feature['geometry'];

      Map<String, dynamic> properties;
      if (rawProperties != null && rawProperties is Map) {
        // Standard GeoJSON format with properties field
        properties = Map<String, dynamic>.from(rawProperties);
      } else {
        // OpenAIP format - extract all fields except geometry as properties
        properties = <String, dynamic>{};
        for (final key in feature.keys) {
          if (key != 'geometry') {
            properties[key] = feature[key];
          }
        }
      }

      final geometry = rawGeometry is Map ? Map<String, dynamic>.from(rawGeometry) : <String, dynamic>{};

      // Parse polygons from GeoJSON
      final polygons = _parsePolygons(geometry);
      if (polygons.isEmpty) {
        return null;
      }

      // Calculate hash for geometry
      final geometryHash = generateGeometryHash(polygons);

      // Extract numeric type code - ensure it's stored as int
      final typeCode = properties['type'] is int
          ? properties['type'] as int
          : (properties['type'] as num?)?.toInt() ?? 0;

      // Convert LatLng polygons to ClipperData for optimal performance
      final clipperData = ClipperData.fromLatLngPolygons(polygons);

      // Create cached geometry object (matching the existing structure)
      return CachedAirspaceGeometry(
        id: id,
        name: properties['name'] ?? 'Unknown',
        typeCode: typeCode,
        clipperData: clipperData,
        properties: properties,
        fetchTime: DateTime.now(),
        geometryHash: geometryHash,
      );
    } catch (e, stack) {
      LoggingService.error('Failed to process geometry $id', e, stack);
      return null;
    }
  }


  /// Retrieve an airspace geometry by ID with memory cache
  Future<CachedAirspaceGeometry?> getGeometry(String id) async {
    final stopwatch = Stopwatch()..start();

    // Check memory cache first
    if (_memoryCache.containsKey(id)) {
      _memoryHits++;
      _updateAccessOrder(id);
      final cached = _memoryCache[id]!;

      // Log memory cache hit for performance monitoring
      if (stopwatch.elapsedMilliseconds > 1) {
        LoggingService.performance(
          '[MEMORY_CACHE_HIT]',
          stopwatch.elapsed,
          'id=$id',
        );
      }
      return cached;
    }

    _memoryMisses++;

    // Query disk cache
    final geometry = await _diskCache.getGeometry(id);

    if (geometry != null) {
      _diskHits++;
      // Add to memory cache
      _addToMemoryCache(id, geometry);

      // Remove redundant disk cache hit logging - already logged in disk cache layer
      return geometry;
    }

    _diskMisses++;
    return null;
  }

  /// Retrieve multiple geometries by IDs with memory cache
  Future<List<CachedAirspaceGeometry>> getGeometries(Set<String> ids) async {
    if (ids.isEmpty) return [];

    final stopwatch = Stopwatch()..start();
    final memoryBefore = PerformanceMonitor.getMemoryUsageMB();
    final geometries = <CachedAirspaceGeometry>[];
    final idsToFetchFromDisk = <String>{};

    // Step 1: Check memory cache first
    for (final id in ids) {
      if (_memoryCache.containsKey(id)) {
        _memoryHits++;
        _updateAccessOrder(id);
        geometries.add(_memoryCache[id]!);
      } else {
        _memoryMisses++;
        idsToFetchFromDisk.add(id);
      }
    }

    // Step 2: Fetch missing from disk if needed
    if (idsToFetchFromDisk.isNotEmpty) {
      final diskGeometries = await _diskCache.getGeometries(idsToFetchFromDisk);

      // Add disk results to memory cache
      for (final geometry in diskGeometries) {
        _diskHits++;
        _addToMemoryCache(geometry.id, geometry);
        geometries.add(geometry);
      }

      _diskMisses += idsToFetchFromDisk.length - diskGeometries.length;
    }

    final memoryAfter = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.performance(
      '[BATCH_GEOMETRY_FETCH_WITH_CACHE]',
      stopwatch.elapsed,
      'requested=${ids.length}, memory_hits=${ids.length - idsToFetchFromDisk.length}, disk_fetched=${idsToFetchFromDisk.length}, found=${geometries.length}',
    );

    // Log memory usage for large batch operations
    if (ids.length > 200) {
      LoggingService.structured('MEMORY_USAGE', {
        'operation': 'batch_geometry_fetch',
        'before_mb': memoryBefore.toStringAsFixed(1),
        'after_mb': memoryAfter.toStringAsFixed(1),
        'delta_mb': (memoryAfter - memoryBefore).toStringAsFixed(1),
        'geometries_loaded': geometries.length,
        'cache_size': _memoryCache.length,
        'cache_limit': _maxMemoryCacheSize,
      });
    }

    return geometries;
  }

  /// Add geometry to memory cache with LRU eviction
  void _addToMemoryCache(String id, CachedAirspaceGeometry geometry) {
    // Remove from current position if exists
    _accessOrder.remove(id);

    // Add to front
    _accessOrder.insert(0, id);
    _memoryCache[id] = geometry;

    // Evict if over limit
    while (_accessOrder.length > _maxMemoryCacheSize) {
      final evictId = _accessOrder.removeLast();
      _memoryCache.remove(evictId);
    }
  }

  /// Update access order for LRU
  void _updateAccessOrder(String id) {
    _accessOrder.remove(id);
    _accessOrder.insert(0, id);
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
              // Safely convert to double, handling both int and double values
              final lat = (coord[1] is int) ? coord[1].toDouble() : coord[1] as double;
              final lng = (coord[0] is int) ? coord[0].toDouble() : coord[0] as double;
              points.add(LatLng(lat, lng));
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
                // Safely convert to double, handling both int and double values
                final lat = (coord[1] is int) ? coord[1].toDouble() : coord[1] as double;
                final lng = (coord[0] is int) ? coord[0].toDouble() : coord[0] as double;
                points.add(LatLng(lat, lng));
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


  /// Track duplicate airspace references
  void _trackDuplicate(String id) {
    _duplicateCount[id] = (_duplicateCount[id] ?? 0) + 1;
  }

  /// Get cache statistics
  Future<CacheStatistics> getStatistics() async {
    final hitRate = (_diskHits + _diskMisses) > 0
        ? _diskHits / (_diskHits + _diskMisses)
        : 0.0;

    final totalDuplicates = _duplicateCount.values.fold(0, (sum, count) => sum + count);

    // Get database statistics
    final dbStats = await _diskCache.getStatisticsMap();

    return CacheStatistics(
      totalGeometries: dbStats['geometry_count'] ?? 0,
      totalTiles: 0, // Will be set by metadata cache
      emptyTiles: 0, // Will be set by metadata cache
      duplicatedAirspaces: totalDuplicates,
      totalMemoryBytes: dbStats['database_size_bytes'] ?? 0, // Use database size
      compressedBytes: dbStats['total_compressed_size'] ?? 0,
      averageCompressionRatio: (dbStats['avg_compression_ratio'] ?? 0).toDouble(),
      cacheHitRate: hitRate,
      lastUpdated: DateTime.now(),
    );
  }

  /// Clear statistics
  void clearStatistics() {
    _memoryHits = 0;
    _memoryMisses = 0;
    _diskHits = 0;
    _diskMisses = 0;
    _duplicateCount.clear();
    LoggingService.info('Cleared airspace geometry statistics');
  }

  /// Clear all cache
  Future<void> clearAllCache() async {
    clearStatistics();
    clearMemoryCache();
    await _diskCache.clearCache();
    LoggingService.info('Cleared all airspace geometry cache (memory and disk)');
  }

  /// Clear memory cache only
  void clearMemoryCache() {
    final entriesRemoved = _memoryCache.length;
    _memoryCache.clear();
    _accessOrder.clear();
    LoggingService.info('Cleared geometry memory cache: $entriesRemoved entries removed');

    // Verify cache is empty
    if (_memoryCache.isEmpty && _accessOrder.isEmpty) {
      LoggingService.info('[MEMORY_CACHE_CLEAR_VERIFIED] Memory cache successfully cleared');
    } else {
      LoggingService.error(
        'Memory cache not fully cleared: cache=${_memoryCache.length}, order=${_accessOrder.length}',
        null,
        null,
      );
    }
  }

  /// Clean expired data
  Future<void> cleanExpiredData() async {
    await _diskCache.cleanExpiredData();
  }

  /// Get cache performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    final totalMemoryOps = _memoryHits + _memoryMisses;
    final totalDiskOps = _diskHits + _diskMisses;

    return {
      'memory': {
        'hits': _memoryHits,
        'misses': _memoryMisses,
        'hitRate': totalMemoryOps > 0
            ? (_memoryHits / totalMemoryOps * 100).toStringAsFixed(1)
            : '0.0',
        'cacheSize': _memoryCache.length,
        'maxSize': _maxMemoryCacheSize,
      },
      'disk': {
        'hits': _diskHits,
        'misses': _diskMisses,
        'hitRate': totalDiskOps > 0
            ? (_diskHits / totalDiskOps * 100).toStringAsFixed(1)
            : '0.0',
      },
      'overall': {
        'hitRate': (totalMemoryOps + totalDiskOps) > 0
            ? ((_memoryHits + _diskHits) / (totalMemoryOps + totalDiskOps) * 100).toStringAsFixed(1)
            : '0.0',
        'duplicatesDetected': _duplicateCount.length,
        'totalDuplicateReferences': _duplicateCount.values.fold(0, (sum, count) => sum + count),
      },
    };
  }
}