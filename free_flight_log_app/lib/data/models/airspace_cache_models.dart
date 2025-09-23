import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../../services/airspace_geojson_service.dart' show ClipperData, AirspaceData, AirspaceStyle;
import 'airspace_enums.dart';

/// Represents a unique airspace geometry stored in the cache
class CachedAirspaceGeometry {
  final String id;
  final String name;
  final int typeCode;  // Store numeric type code instead of string
  final ClipperData clipperData;  // Always use ClipperData for optimal performance
  final Map<String, dynamic> properties;
  final DateTime fetchTime;
  final String geometryHash;
  final int compressedSize;
  final int uncompressedSize;
  final int? lowerAltitudeFt;  // Pre-computed altitude from database

  // Cached computed values to avoid redundant calculations
  fm.LatLngBounds? _cachedBounds;
  AirspaceData? _cachedAirspaceData;
  AirspaceStyle? _cachedStyle;

  CachedAirspaceGeometry({
    required this.id,
    required this.name,
    required this.typeCode,
    required this.clipperData,
    required this.properties,
    required this.fetchTime,
    required this.geometryHash,
    this.compressedSize = 0,
    this.uncompressedSize = 0,
    this.lowerAltitudeFt,
  });

  // fromJson and toJson methods removed - data loaded directly from database

  /// Get cached bounds or calculate and cache if not available
  fm.LatLngBounds getBounds() {
    if (_cachedBounds != null) return _cachedBounds!;

    // Calculate bounds from ClipperData
    _cachedBounds = _calculateBoundsFromClipperData();
    return _cachedBounds!;
  }

  /// Get cached AirspaceData or create and cache if not available
  AirspaceData getAirspaceData() {
    if (_cachedAirspaceData != null) return _cachedAirspaceData!;

    // Create AirspaceData from properties
    _cachedAirspaceData = _createAirspaceDataFromProperties();
    return _cachedAirspaceData!;
  }

  /// Get cached style or compute and cache if not available
  AirspaceStyle getStyle(AirspaceStyle Function(AirspaceData) styleResolver) {
    if (_cachedStyle != null) return _cachedStyle!;

    // Compute style using the provided resolver
    _cachedStyle = styleResolver(getAirspaceData());
    return _cachedStyle!;
  }

  /// Calculate bounds from ClipperData coordinates
  fm.LatLngBounds _calculateBoundsFromClipperData() {
    const double coordPrecision = 10000000.0;

    double minLat = 90.0, maxLat = -90.0;
    double minLng = 180.0, maxLng = -180.0;

    // Iterate through coordinates (stored as lng,lat pairs in Int32)
    for (int i = 0; i < clipperData.coords.length; i += 2) {
      final lng = clipperData.coords[i] / coordPrecision;
      final lat = clipperData.coords[i + 1] / coordPrecision;

      minLat = lat < minLat ? lat : minLat;
      maxLat = lat > maxLat ? lat : maxLat;
      minLng = lng < minLng ? lng : minLng;
      maxLng = lng > maxLng ? lng : maxLng;
    }

    return fm.LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  /// Create AirspaceData from properties
  AirspaceData _createAirspaceDataFromProperties() {
    final icaoClass = (properties['class'] ?? properties['icaoClass']) as int?;
    final upperLimit = properties['upperLimit'] as Map<String, dynamic>?;
    final lowerLimit = properties['lowerLimit'] as Map<String, dynamic>?;
    final country = properties['country'] as String?;

    return AirspaceData(
      name: name,
      type: AirspaceType.fromCode(typeCode),
      icaoClass: IcaoClass.fromCode(icaoClass),
      upperLimit: upperLimit,
      lowerLimit: lowerLimit,
      country: country,
      lowerAltitudeFt: lowerAltitudeFt,
    );
  }

  /// Clear cached values (useful when properties are updated)
  void clearCache() {
    _cachedBounds = null;
    _cachedAirspaceData = null;
    _cachedStyle = null;
  }

  // Helper methods removed - using ClipperData for all geometry operations

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