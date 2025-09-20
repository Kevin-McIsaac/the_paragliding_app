import 'package:latlong2/latlong.dart';
import '../../services/airspace_geojson_service.dart' show ClipperData;

/// Represents a unique airspace geometry stored in the cache
class CachedAirspaceGeometry {
  final String id;
  final String name;
  final int typeCode;  // Store numeric type code instead of string
  final List<List<LatLng>>? polygons;  // Made optional - either polygons or clipperData
  final ClipperData? clipperData;  // Alternative to polygons for direct clipping
  final Map<String, dynamic> properties;
  final DateTime fetchTime;
  final String geometryHash;
  final int compressedSize;
  final int uncompressedSize;
  final int? lowerAltitudeFt;  // Pre-computed altitude from database

  CachedAirspaceGeometry({
    required this.id,
    required this.name,
    required this.typeCode,
    this.polygons,  // Now optional
    this.clipperData,  // New optional field
    required this.properties,
    required this.fetchTime,
    required this.geometryHash,
    this.compressedSize = 0,
    this.uncompressedSize = 0,
    this.lowerAltitudeFt,
  }) : assert(polygons != null || clipperData != null, 'Either polygons or clipperData must be provided');

  factory CachedAirspaceGeometry.fromJson(Map<String, dynamic> json) {
    return CachedAirspaceGeometry(
      id: json['id'] as String,
      name: json['name'] as String,
      typeCode: json['typeCode'] as int? ?? json['type'] as int? ?? 0,  // Handle old 'type' field for compatibility
      polygons: _parsePolygons(json['polygons']),
      properties: Map<String, dynamic>.from(json['properties'] ?? {}),
      fetchTime: DateTime.parse(json['fetchTime'] as String),
      geometryHash: json['geometryHash'] as String,
      compressedSize: json['compressedSize'] ?? 0,
      uncompressedSize: json['uncompressedSize'] ?? 0,
      lowerAltitudeFt: json['lowerAltitudeFt'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'typeCode': typeCode,  // Store as numeric type code
      'polygons': polygons != null ? _encodePolygons(polygons!) : null,
      'properties': properties,
      'fetchTime': fetchTime.toIso8601String(),
      'geometryHash': geometryHash,
      'compressedSize': compressedSize,
      'uncompressedSize': uncompressedSize,
      'lowerAltitudeFt': lowerAltitudeFt,
    };
  }

  static List<List<LatLng>> _parsePolygons(dynamic data) {
    if (data is List) {
      return data.map((polygon) {
        if (polygon is List) {
          return polygon.map((point) {
            if (point is List && point.length >= 2) {
              // Safely convert to double, handling both int and double values
              final lat = (point[1] is int) ? point[1].toDouble() : point[1] as double;
              final lng = (point[0] is int) ? point[0].toDouble() : point[0] as double;
              return LatLng(lat, lng);
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