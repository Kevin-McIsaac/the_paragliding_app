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

  // Statistics tracking
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
      LoggingService.debug('Storing geometry for airspace ID: $id');

      // Log feature structure
      LoggingService.debug('Feature keys: ${feature.keys.toList()}');

      // The OpenAIP API returns features with properties at the top level, not in a 'properties' field
      // Check if properties is a separate field (standard GeoJSON) or if properties are at top level (OpenAIP format)
      final rawProperties = feature['properties'];
      final rawGeometry = feature['geometry'];

      LoggingService.debug('Raw properties type: ${rawProperties.runtimeType}');
      LoggingService.debug('Raw geometry type: ${rawGeometry.runtimeType}');

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
        LoggingService.debug('Extracted OpenAIP properties: name=${properties['name']}, type=${properties['type']}');
      }

      final geometry = rawGeometry is Map ? Map<String, dynamic>.from(rawGeometry) : <String, dynamic>{};

      if (geometry.isNotEmpty) {
        LoggingService.debug('Geometry type: ${geometry['type']}, has coordinates: ${geometry['coordinates'] != null}');
      }

      // Parse polygons from GeoJSON
      final polygons = _parsePolygons(geometry);
      if (polygons.isEmpty) {
        LoggingService.debug('Skipping airspace with no valid polygons: $id');
        return;
      }

      LoggingService.debug('Parsed ${polygons.length} polygons for airspace $id');

      final geometryHash = generateGeometryHash(polygons);

      // Check if geometry already exists and is unchanged
      final existing = await getGeometry(id);
      if (existing != null && existing.geometryHash == geometryHash) {
        LoggingService.debug('Geometry unchanged, skipping update: $id');
        _trackDuplicate(id);
        return;
      }

      // Create cached geometry object
      // Extract numeric type code - ensure it's stored as int
      final typeCode = properties['type'] is int
          ? properties['type'] as int
          : (properties['type'] as num?)?.toInt() ?? 0;

      final cachedGeometry = CachedAirspaceGeometry(
        id: id,
        name: properties['name'] ?? 'Unknown',
        typeCode: typeCode,  // Store numeric type code
        polygons: polygons,
        properties: properties,
        fetchTime: DateTime.now(),
        geometryHash: geometryHash,
      );

      // Store to disk only
      await _diskCache.putGeometry(cachedGeometry);

      LoggingService.performance(
        'Stored airspace geometry',
        stopwatch.elapsed,
        'id=$id, polygons=${polygons.length}, name=${cachedGeometry.name}, typeCode=${cachedGeometry.typeCode}',
      );
      LoggingService.info('Successfully stored airspace: $id (${cachedGeometry.name})');
    } catch (e, stack) {
      LoggingService.error('Failed to store geometry', e, stack);
    }
  }

  /// Retrieve an airspace geometry by ID
  Future<CachedAirspaceGeometry?> getGeometry(String id) async {
    // Query disk cache directly
    final geometry = await _diskCache.getGeometry(id);

    if (geometry != null) {
      _diskHits++;
      LoggingService.debug('Disk cache hit for geometry: $id');
      return geometry;
    }

    _diskMisses++;
    LoggingService.debug('Cache miss for geometry: $id');
    return null;
  }

  /// Retrieve multiple geometries by IDs
  Future<List<CachedAirspaceGeometry>> getGeometries(Set<String> ids) async {
    if (ids.isEmpty) return [];

    final stopwatch = Stopwatch()..start();

    // Fetch all from disk directly
    final geometries = await _diskCache.getGeometries(ids);

    _diskHits += geometries.length;
    _diskMisses += ids.length - geometries.length;

    LoggingService.performance(
      'Retrieved multiple geometries',
      stopwatch.elapsed,
      'requested=${ids.length}, found=${geometries.length}',
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
    _diskHits = 0;
    _diskMisses = 0;
    _duplicateCount.clear();
    LoggingService.info('Cleared airspace geometry statistics');
  }

  /// Clear all cache
  Future<void> clearAllCache() async {
    clearStatistics();
    await _diskCache.clearCache();
    LoggingService.info('Cleared all airspace geometry cache');
  }

  /// Clean expired data
  Future<void> cleanExpiredData() async {
    await _diskCache.cleanExpiredData();
  }

  /// Get cache performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'diskHits': _diskHits,
      'diskMisses': _diskMisses,
      'hitRate': (_diskHits + _diskMisses) > 0
          ? (_diskHits / (_diskHits + _diskMisses) * 100).toStringAsFixed(1)
          : '0.0',
      'duplicatesDetected': _duplicateCount.length,
      'totalDuplicateReferences': _duplicateCount.values.fold(0, (sum, count) => sum + count),
    };
  }
}