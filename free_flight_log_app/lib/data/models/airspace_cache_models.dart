import 'package:latlong2/latlong.dart';

/// Represents a unique airspace geometry stored in the cache
class CachedAirspaceGeometry {
  final String id;
  final String name;
  final String type;
  final List<List<LatLng>> polygons;
  final Map<String, dynamic> properties;
  final DateTime fetchTime;
  final String geometryHash;
  final int compressedSize;
  final int uncompressedSize;

  CachedAirspaceGeometry({
    required this.id,
    required this.name,
    required this.type,
    required this.polygons,
    required this.properties,
    required this.fetchTime,
    required this.geometryHash,
    this.compressedSize = 0,
    this.uncompressedSize = 0,
  });

  factory CachedAirspaceGeometry.fromJson(Map<String, dynamic> json) {
    return CachedAirspaceGeometry(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      polygons: _parsePolygons(json['polygons']),
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
      fetchTime: DateTime.parse(json['fetchTime'] as String),
      geometryHash: json['geometryHash'] as String,
      compressedSize: json['compressedSize'] ?? 0,
      uncompressedSize: json['uncompressedSize'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'polygons': _encodePolygons(polygons),
      'properties': properties,
      'fetchTime': fetchTime.toIso8601String(),
      'geometryHash': geometryHash,
      'compressedSize': compressedSize,
      'uncompressedSize': uncompressedSize,
    };
  }

  static List<List<LatLng>> _parsePolygons(dynamic data) {
    if (data is List) {
      return data.map((polygon) {
        if (polygon is List) {
          return polygon.map((point) {
            if (point is List && point.length >= 2) {
              return LatLng(point[1].toDouble(), point[0].toDouble());
            }
            return LatLng(0, 0);
          }).toList();
        }
        return <LatLng>[];
      }).toList();
    }
    return [];
  }

  static List<List<List<double>>> _encodePolygons(List<List<LatLng>> polygons) {
    return polygons.map((polygon) {
      return polygon.map((point) {
        return [point.longitude, point.latitude];
      }).toList();
    }).toList();
  }

  bool get isExpired {
    final age = DateTime.now().difference(fetchTime);
    return age.inDays > 7;
  }

  double get compressionRatio {
    if (uncompressedSize == 0) return 0;
    return 1.0 - (compressedSize / uncompressedSize);
  }
}

/// Represents tile metadata that maps tiles to airspace IDs
class TileMetadata {
  final String tileKey;
  final Set<String> airspaceIds;
  final DateTime fetchTime;
  final int airspaceCount;
  final bool isEmpty;
  final Map<String, dynamic>? statistics;

  TileMetadata({
    required this.tileKey,
    required this.airspaceIds,
    required this.fetchTime,
    required this.airspaceCount,
    required this.isEmpty,
    this.statistics,
  });

  factory TileMetadata.empty(String tileKey) {
    return TileMetadata(
      tileKey: tileKey,
      airspaceIds: {},
      fetchTime: DateTime.now(),
      airspaceCount: 0,
      isEmpty: true,
      statistics: null,
    );
  }

  factory TileMetadata.fromJson(Map<String, dynamic> json) {
    return TileMetadata(
      tileKey: json['tileKey'] as String,
      airspaceIds: Set<String>.from(json['airspaceIds'] ?? []),
      fetchTime: DateTime.parse(json['fetchTime'] as String),
      airspaceCount: json['airspaceCount'] ?? 0,
      isEmpty: json['isEmpty'] ?? false,
      statistics: json['statistics'] != null
          ? Map<String, dynamic>.from(json['statistics'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tileKey': tileKey,
      'airspaceIds': airspaceIds.toList(),
      'fetchTime': fetchTime.toIso8601String(),
      'airspaceCount': airspaceCount,
      'isEmpty': isEmpty,
      'statistics': statistics,
    };
  }

  bool get isExpired {
    final age = DateTime.now().difference(fetchTime);
    return age.inHours > 24;
  }

  int get estimatedSize {
    // Rough estimate: 100 bytes base + 30 bytes per airspace ID
    return 100 + (airspaceIds.length * 30);
  }
}

/// Statistics for cache performance monitoring
class CacheStatistics {
  final int totalGeometries;
  final int totalTiles;
  final int emptyTiles;
  final int duplicatedAirspaces;
  final int totalMemoryBytes;
  final int compressedBytes;
  final double averageCompressionRatio;
  final double cacheHitRate;
  final DateTime lastUpdated;

  CacheStatistics({
    required this.totalGeometries,
    required this.totalTiles,
    required this.emptyTiles,
    required this.duplicatedAirspaces,
    required this.totalMemoryBytes,
    required this.compressedBytes,
    required this.averageCompressionRatio,
    required this.cacheHitRate,
    required this.lastUpdated,
  });

  factory CacheStatistics.empty() {
    return CacheStatistics(
      totalGeometries: 0,
      totalTiles: 0,
      emptyTiles: 0,
      duplicatedAirspaces: 0,
      totalMemoryBytes: 0,
      compressedBytes: 0,
      averageCompressionRatio: 0,
      cacheHitRate: 0,
      lastUpdated: DateTime.now(),
    );
  }

  double get memoryReductionPercent {
    if (totalMemoryBytes == 0) return 0;
    return ((totalMemoryBytes - compressedBytes) / totalMemoryBytes) * 100;
  }

  double get emptyTilePercent {
    if (totalTiles == 0) return 0;
    return (emptyTiles / totalTiles) * 100;
  }

  Map<String, dynamic> toJson() {
    return {
      'totalGeometries': totalGeometries,
      'totalTiles': totalTiles,
      'emptyTiles': emptyTiles,
      'duplicatedAirspaces': duplicatedAirspaces,
      'totalMemoryBytes': totalMemoryBytes,
      'compressedBytes': compressedBytes,
      'averageCompressionRatio': averageCompressionRatio,
      'cacheHitRate': cacheHitRate,
      'memoryReductionPercent': memoryReductionPercent,
      'emptyTilePercent': emptyTilePercent,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

/// Represents a cache operation result
class CacheResult<T> {
  final T? data;
  final bool isHit;
  final bool isExpired;
  final Duration? fetchDuration;
  final String? error;

  CacheResult({
    this.data,
    required this.isHit,
    this.isExpired = false,
    this.fetchDuration,
    this.error,
  });

  bool get isSuccess => data != null && error == null;
  bool get isMiss => !isHit;

  factory CacheResult.hit(T data, {bool expired = false}) {
    return CacheResult(
      data: data,
      isHit: true,
      isExpired: expired,
    );
  }

  factory CacheResult.miss({Duration? fetchDuration}) {
    return CacheResult(
      isHit: false,
      fetchDuration: fetchDuration,
    );
  }

  factory CacheResult.error(String error) {
    return CacheResult(
      isHit: false,
      error: error,
    );
  }
}