import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geobase/geobase.dart' as geo;
import 'package:clipper2/clipper2.dart' as clipper;
import '../services/logging_service.dart';
import '../services/airspace_identification_service.dart';
import '../services/airspace_metadata_cache.dart';
import '../services/airspace_geometry_cache.dart';
import '../services/airspace_disk_cache.dart';
import '../services/airspace_performance_logger.dart';
import '../services/airspace_country_service.dart';
import '../data/models/airspace_cache_models.dart';
import '../data/models/airspace_enums.dart';
import '../utils/performance_monitor.dart';

/// Data structure for airspace information
class AirspaceData {
  final String name;
  final AirspaceType type;
  final IcaoClass icaoClass;
  final Map<String, dynamic>? upperLimit;
  final Map<String, dynamic>? lowerLimit;
  final String? country;
  final int? lowerAltitudeFt; // Pre-computed altitude from database

  /// Indicates if this airspace is currently filtered out by user settings
  /// Used to show visual distinction in tooltips
  bool isCurrentlyFiltered = false;

  AirspaceData({
    required this.name,
    required this.type,
    required this.icaoClass,
    this.upperLimit,
    this.lowerLimit,
    this.country,
    this.lowerAltitudeFt,
  });

  /// Convert lower altitude limit to feet for sorting purposes
  /// GND = 0, ft AMSL = direct value, FL = value × 100
  int getLowerAltitudeInFeet() {
    // Use pre-computed value if available
    if (lowerAltitudeFt != null) return lowerAltitudeFt!;

    if (lowerLimit == null) return 999999; // Put unknown altitudes at the end

    final value = lowerLimit!['value'];
    final unit = lowerLimit!['unit'];
    final reference = lowerLimit!['reference'];

    // Handle special ground values or reference code 0 (GND)
    if (reference == 0 || (value is String && value.toLowerCase() == 'gnd')) {
      return 0;
    }

    // Handle numeric values with OpenAIP unit codes
    if (value is num) {
      // OpenAIP unit codes: 1=ft, 2=m, 6=FL
      if (unit == 6) {
        // Flight Level: FL090 = 9,000 feet
        return (value * 100).round();
      } else if (unit == 1) {
        // Feet (AMSL or AGL - treat both as feet for sorting)
        return value.round();
      } else if (unit == 2) {
        // Meters - convert to feet
        return (value * 3.28084).round();
      }
    }

    // Fallback: if unit is string (processed data)
    if (unit is String) {
      final unitStr = unit.toString().toLowerCase();
      if (value is num) {
        if (unitStr == 'fl') {
          return (value * 100).round();
        } else if (unitStr == 'ft') {
          return value.round();
        } else if (unitStr == 'm') {
          return (value * 3.28084).round();
        }
      }
    }

    // Default case - try to parse as number in feet
    if (value is num) {
      return value.round();
    }
    return 999999; // Unknown - put at end
  }

  /// Convert upper altitude limit to feet for sorting purposes
  /// GND = 0, ft AMSL = direct value, FL = value × 100
  int getUpperAltitudeInFeet() {
    if (upperLimit == null) return 999999; // Put unknown altitudes at the end

    final value = upperLimit!['value'];
    final unit = upperLimit!['unit'];
    final reference = upperLimit!['reference'];

    // Handle special ground values or reference code 0 (GND)
    if (reference == 0 || (value is String && value.toLowerCase() == 'gnd')) {
      return 0;
    }

    // Handle numeric values with OpenAIP unit codes
    if (value is num) {
      // OpenAIP unit codes: 1=ft, 2=m, 6=FL
      if (unit == 6) {
        // Flight Level: FL090 = 9,000 feet
        return (value * 100).round();
      } else if (unit == 1) {
        // Feet (AMSL or AGL - treat both as feet for sorting)
        return value.round();
      } else if (unit == 2) {
        // Meters - convert to feet
        return (value * 3.28084).round();
      }
    }

    // Fallback: if unit is string (processed data)
    if (unit is String) {
      final unitStr = unit.toString().toLowerCase();
      if (value is num) {
        if (unitStr == 'fl') {
          return (value * 100).round();
        } else if (unitStr == 'ft') {
          return value.round();
        } else if (unitStr == 'm') {
          return (value * 3.28084).round();
        }
      }
    }

    // Default case - try to parse as number in feet
    if (value is num) {
      return value.round();
    }
    return 999999; // Unknown - put at end
  }

  /// Format altitude limit for display
  String formatAltitude(Map<String, dynamic>? limit) {
    if (limit == null) return 'Unknown';

    final value = limit['value'];
    final unit = limit['unit'] ?? '';
    final reference = limit['reference'] ?? '';

    if (value == null) return 'Unknown';

    // Handle special values
    if (value is String) {
      if (value.toLowerCase() == 'gnd' || value.toLowerCase() == 'sfc') {
        return 'Ground';
      }
      if (value.toLowerCase() == 'unlimited' || value.toLowerCase() == 'unl') {
        return 'Unlimited';
      }
    }

    // Format numeric values
    final valueStr = value is num ? value.round().toString() : value.toString();

    // Handle unit formatting (convert codes to readable units)
    String unitStr = '';
    if (unit == 1 || unit == 'ft') {
      unitStr = 'ft';
    } else if (unit == 2 || unit == 'm') {
      unitStr = 'm';
    } else if (unit == 6 || unit == 'FL') {
      unitStr = 'FL';
    } else if (unit is String && unit.isNotEmpty) {
      unitStr = unit; // Use string unit as-is
    }

    // Handle reference formatting (convert codes to readable references)
    String refStr = '';
    if (reference == 1 || reference == 'AMSL') {
      refStr = ' AMSL';
    } else if (reference == 2 || reference == 'AGL') {
      refStr = ' AGL';
    } else if (reference is String && reference.isNotEmpty && reference != '0') {
      refStr = ' $reference';
    }

    return '$valueStr$unitStr$refStr'.trim();
  }

  String get upperAltitude => formatAltitude(upperLimit);
  String get lowerAltitude => formatAltitude(lowerLimit);
}

/// Style configuration for different airspace types
class AirspaceStyle {
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final bool isDotted;
  final fm.StrokePattern? pattern;

  const AirspaceStyle({
    required this.fillColor,
    required this.borderColor,
    this.borderWidth = 1.5,
    this.isDotted = false,
    this.pattern,
  });
}

/// Struct-of-Arrays pattern for better cache locality during clipping operations
/// This optimizes memory access patterns by storing related data contiguously
class ClippingBatch {
  // Core data arrays - all contiguous in memory for better cache usage
  final List<ClipperData?> clipperData;      // Clipper data for each airspace
  final List<int> polygonIndices;            // Polygon index within ClipperData
  final Int32List altitudes;                 // Altitude in feet (packed for cache)
  final Float32List bounds;                  // Bounds as [west, south, east, north] * n
  final List<AirspacePolygonData> airspaceData; // Full airspace data

  // Pre-allocated buffers for reuse
  final List<clipper.Path64> pathBuffer;     // Reusable path extraction buffer
  int count = 0;                              // Number of airspaces in batch

  ClippingBatch(int capacity) :
    clipperData = List<ClipperData?>.filled(capacity, null),
    polygonIndices = List<int>.filled(capacity, 0),
    altitudes = Int32List(capacity),
    bounds = Float32List(capacity * 4),  // 4 floats per bounds
    airspaceData = List<AirspacePolygonData>.filled(capacity,
      AirspacePolygonData(
        points: const [],
        airspaceData: AirspaceData(
          name: '',
          type: AirspaceType.other,
          icaoClass: IcaoClass.none,
          upperLimit: null,
          lowerLimit: null,
          country: null,
          lowerAltitudeFt: null,
        ),
      ),
    ),
    pathBuffer = List<clipper.Path64>.filled(capacity, const []);

  /// Add an airspace to the batch
  void add({
    required ClipperData? clipper,
    required int polygonIndex,
    required int altitude,
    required fm.LatLngBounds boundsData,
    required AirspacePolygonData data,
  }) {
    if (count >= clipperData.length) {
      throw StateError('ClippingBatch capacity exceeded');
    }

    clipperData[count] = clipper;
    polygonIndices[count] = polygonIndex;
    altitudes[count] = altitude;

    // Pack bounds into Float32List for contiguous access
    final idx = count * 4;
    bounds[idx] = boundsData.west;
    bounds[idx + 1] = boundsData.south;
    bounds[idx + 2] = boundsData.east;
    bounds[idx + 3] = boundsData.north;

    airspaceData[count] = data;
    count++;
  }

  /// Get bounds for an airspace (faster than accessing LatLngBounds objects)
  (double west, double south, double east, double north) getBounds(int index) {
    final idx = index * 4;
    return (bounds[idx], bounds[idx + 1], bounds[idx + 2], bounds[idx + 3]);
  }

  /// Check if bounds overlap (inline for performance)
  bool boundsOverlap(int index1, int index2) {
    final idx1 = index1 * 4;
    final idx2 = index2 * 4;
    return !(bounds[idx1 + 2] < bounds[idx2] ||      // east1 < west2
             bounds[idx1] > bounds[idx2 + 2] ||      // west1 > east2
             bounds[idx1 + 3] < bounds[idx2 + 1] ||  // north1 < south2
             bounds[idx1 + 1] > bounds[idx2 + 3]);   // south1 > north2
  }

  /// Clear the batch for reuse
  void clear() {
    count = 0;
  }
}


/// Container for clipped polygon data
class _ClippedPolygonData {
  final List<LatLng> outerPoints;
  final List<List<LatLng>> holes;
  final AirspaceData airspaceData;
  final AirspaceStyle style;

  _ClippedPolygonData({
    required this.outerPoints,
    required this.holes,
    required this.airspaceData,
    required this.style,
  });
}


/// Service for fetching and parsing airspace data from OpenAIP Core API
class AirspaceGeoJsonService {
  static AirspaceGeoJsonService? _instance;
  static AirspaceGeoJsonService get instance => _instance ??= AirspaceGeoJsonService._();

  AirspaceGeoJsonService._();

  final AirspaceMetadataCache _metadataCache = AirspaceMetadataCache.instance;
  final AirspaceGeometryCache _geometryCache = AirspaceGeometryCache.instance;
  final AirspacePerformanceLogger _performanceLogger = AirspacePerformanceLogger.instance;


  // Initialize performance monitoring
  void initialize() {
    _performanceLogger.startPeriodicLogging(interval: const Duration(minutes: 2));
  }

  // Track currently visible airspace types
  Set<AirspaceType> _currentVisibleTypes = <AirspaceType>{};

  /// Get the currently visible airspace types in the loaded data
  Set<AirspaceType> get visibleAirspaceTypes => Set.from(_currentVisibleTypes);

  // ICAO class-based color mapping - Uses colors from IcaoClass enum for single source of truth
  static Map<IcaoClass, AirspaceStyle> get _icaoClassStyles => {
    IcaoClass.classA: AirspaceStyle(
      fillColor: IcaoClass.classA.fillColor,
      borderColor: IcaoClass.classA.borderColor,
      borderWidth: 2.0,
    ),
    IcaoClass.classB: AirspaceStyle(
      fillColor: IcaoClass.classB.fillColor,
      borderColor: IcaoClass.classB.borderColor,
      borderWidth: 1.8,
    ),
    IcaoClass.classC: AirspaceStyle(
      fillColor: IcaoClass.classC.fillColor,
      borderColor: IcaoClass.classC.borderColor,
      borderWidth: 1.6,
    ),
    IcaoClass.classD: AirspaceStyle(
      fillColor: IcaoClass.classD.fillColor,
      borderColor: IcaoClass.classD.borderColor,
      borderWidth: 1.5,
    ),
    IcaoClass.classE: AirspaceStyle(
      fillColor: IcaoClass.classE.fillColor,
      borderColor: IcaoClass.classE.borderColor,
      borderWidth: 1.4,
    ),
    IcaoClass.classF: AirspaceStyle(
      fillColor: IcaoClass.classF.fillColor,
      borderColor: IcaoClass.classF.borderColor,
      borderWidth: 1.3,
    ),
    IcaoClass.classG: AirspaceStyle(
      fillColor: IcaoClass.classG.fillColor,
      borderColor: IcaoClass.classG.borderColor,
      borderWidth: 1.2,
    ),
    IcaoClass.none: AirspaceStyle(
      fillColor: IcaoClass.none.fillColor,
      borderColor: IcaoClass.none.borderColor,
      borderWidth: 1.0,
    ),
  };

  // Fallback airspace type to style mapping for airspaces without ICAO class
  static const Map<String, AirspaceStyle> _airspaceTypeFallbackStyles = {
    'CTR': AirspaceStyle(
      fillColor: Color(0x1AFF0000),  // 10% opacity red
      borderColor: Color(0xFFFF0000),
      borderWidth: 2.0,
    ),
    'TMA': AirspaceStyle(
      fillColor: Color(0x1AFFA500),  // 10% opacity orange
      borderColor: Color(0xFFFFA500),
      borderWidth: 1.8,
    ),
    'CTA': AirspaceStyle(
      fillColor: Color(0x1A0000FF),  // 10% opacity blue
      borderColor: Color(0xFF0000FF),
      borderWidth: 1.5,
    ),
    'D': AirspaceStyle( // Danger
      fillColor: Color(0x1AFF0000),  // 10% opacity red
      borderColor: Color(0xFFFF0000),
      borderWidth: 2.0,
      isDotted: true,
    ),
    'R': AirspaceStyle( // Restricted
      fillColor: Color(0x1AFF4500),  // 10% opacity orange-red
      borderColor: Color(0xFFFF4500),
      borderWidth: 2.0,
    ),
    'P': AirspaceStyle( // Prohibited
      fillColor: Color(0x1A8B0000),  // 10% opacity dark red
      borderColor: Color(0xFF8B0000),
      borderWidth: 2.5,
    ),
    'FIR': AirspaceStyle( // Flight Information Region
      fillColor: Color(0x1A808080),  // 10% opacity gray
      borderColor: Color(0xFF808080),
      borderWidth: 1.0,
    ),
    'OTHER': AirspaceStyle( // Other/Unknown
      fillColor: Color(0x1AC0C0C0),  // 10% opacity light gray
      borderColor: Color(0xFFC0C0C0),
      borderWidth: 1.0,
    ),
  };

  /// Calculate bounding box for API request based on center and zoom level
  fm.LatLngBounds calculateBoundingBox(LatLng center, double zoom) {
    // Adaptive bbox size based on zoom level
    double latRange, lngRange;

    if (zoom < 7) {
      // Very wide area - country/continent level
      // Increased ranges to ensure full coverage including outlying areas like Tasmania
      latRange = 20.0;  // Covers ±20° from center (was 10.0)
      lngRange = 30.0;  // Covers ±30° from center (was 15.0)
    } else if (zoom < 10) {
      // Regional level
      latRange = 10.0;  // Increased from 5.0
      lngRange = 15.0;  // Increased from 7.0
    } else if (zoom < 13) {
      // Local area
      latRange = 2.0;
      lngRange = 3.0;
    } else {
      // Detailed view
      latRange = 1.0;
      lngRange = 1.5;
    }

    final south = (center.latitude - latRange).clamp(-90.0, 90.0);
    final north = (center.latitude + latRange).clamp(-90.0, 90.0);
    final west = (center.longitude - lngRange).clamp(-180.0, 180.0);
    final east = (center.longitude + lngRange).clamp(-180.0, 180.0);

    return fm.LatLngBounds(LatLng(south, west), LatLng(north, east));
  }


  /// Check if any countries are loaded
  Future<bool> hasLoadedCountries() async {
    // Since we no longer track by country, check if we have any geometries
    final geometryCount = await AirspaceDiskCache.instance.getGeometryCount();
    return geometryCount > 0;
  }


  /// Fetch airspace polygons directly without GeoJSON conversion (optimized)
  Future<List<fm.Polygon>> fetchAirspacePolygonsDirect(
    fm.LatLngBounds bounds,
    double opacity,
    Set<AirspaceType> excludedTypes,
    Set<IcaoClass> excludedClasses,
    double maxAltitudeFt,
    bool enableClipping,
  ) async {
    final overallStopwatch = Stopwatch()..start();
    final memoryBefore = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structuredLazy('DIRECT_POLYGON_FETCH', () => {
      'bounds': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      'max_altitude_ft': maxAltitudeFt,
      'clipping_enabled': enableClipping,
    });

    // Convert excluded types to integer codes for SQL filtering
    final excludedTypeCodes = excludedTypes.map((type) => type.code).toSet();
    final excludedClassCodes = excludedClasses.map((cls) => cls.code).toSet();

    // Get airspaces with SQL-level filtering
    // Request ClipperData when clipping is enabled for optimal performance
    final geometries = await _metadataCache.getAirspacesForViewport(
      west: bounds.west,
      south: bounds.south,
      east: bounds.east,
      north: bounds.north,
      excludedTypes: excludedTypeCodes,
      excludedClasses: excludedClassCodes,
      maxAltitudeFt: maxAltitudeFt,
      orderByAltitude: enableClipping, // Order by altitude when clipping is enabled
    );

    // Convert directly to Flutter Map polygons
    final processingStopwatch = Stopwatch()..start();
    final polygons = await _processGeometriesToPolygons(
      geometries,
      opacity,
      bounds,
      enableClipping,
    );
    processingStopwatch.stop();

    overallStopwatch.stop();
    final memoryAfter = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structuredLazy('DIRECT_POLYGON_COMPLETE', () => {
      'total_ms': overallStopwatch.elapsedMilliseconds,
      'processing_ms': processingStopwatch.elapsedMilliseconds,
      'polygon_count': polygons.length,
      'memory_delta_mb': (memoryAfter - memoryBefore).toStringAsFixed(1),
    });

    return polygons;
  }




  // Removed unused OpenAIP mappings: _openAipUnits, _openAipReferenceDatums



  /// Create a flutter_map Polygon from a geobase geometry
  /// Returns both the styled polygon and the coordinate points for identification


  /// Get default style for unknown airspace types
  AirspaceStyle _getDefaultStyle() {
    return const AirspaceStyle(
      fillColor: Color(0x20808080),
      borderColor: Color(0xFF808080),
      borderWidth: 1.0,
    );
  }

  // Removed unused OpenAIP type codes mapping


  /// Get style for airspace data (ICAO class takes priority, fallback to type)
  AirspaceStyle getStyleForAirspace(AirspaceData airspaceData) {
    // Special overrides for critical airspace types (override ICAO class colors)
    if (airspaceData.type == AirspaceType.restricted || airspaceData.type == AirspaceType.prohibited) {
      // Dark red override for R (restricted) and P (prohibited) areas
      const darkRed = Color(0xFF8B0000);
      return AirspaceStyle(
        fillColor: darkRed.withValues(alpha: 0.3), // 30% opacity
        borderColor: darkRed,
        borderWidth: 1.5,
      );
    }

    // Primary: Use ICAO class if available
    if (airspaceData.icaoClass != null) {
      final icaoStyle = _icaoClassStyles[airspaceData.icaoClass];
      if (icaoStyle != null) {
        return icaoStyle;
      }
    }

    // Fallback: Use airspace type
    return getStyleForType(airspaceData.type);
  }

  /// Get style for airspace type (fallback for when ICAO class is not available)
  AirspaceStyle getStyleForType(AirspaceType type) {
    return _airspaceTypeFallbackStyles[type.abbreviation.toUpperCase()] ?? _getDefaultStyle();
  }

  /// Get style for ICAO class (for legend/UI purposes)
  AirspaceStyle? getStyleForIcaoClass(IcaoClass icaoClass) {
    return _icaoClassStyles[icaoClass];
  }

  /// Get all defined ICAO class styles
  Map<IcaoClass, AirspaceStyle> get allIcaoClassStyles => Map.from(_icaoClassStyles);

  /// Get all defined airspace type styles (fallback)
  Map<String, AirspaceStyle> get allAirspaceStyles => Map.from(_airspaceTypeFallbackStyles);

  // ==========================================================================
  // POLYGON CLIPPING METHODS
  // ==========================================================================

  // REMOVED: Float64 conversion methods - now using ClipperData with direct Int32→Int64 conversion

  /// Convert clipper2 Path64 to List of LatLng for final display only
  List<LatLng> _clipperPathToLatLngList(clipper.Path64 path) {
    const double coordPrecision = 10000000.0;
    return path.map((point) => LatLng(
      point.y / coordPrecision,
      point.x / coordPrecision,
    )).toList();
  }


  /// Get cached bounds from geometry or calculate if needed
  fm.LatLngBounds _getBoundsFromGeometry(CachedAirspaceGeometry geometry) {
    return geometry.getBounds();
  }

  /// Check if two bounding boxes overlap
  bool _boundingBoxesOverlap(fm.LatLngBounds box1, fm.LatLngBounds box2) {
    // Check if box1 is completely to the left, right, above, or below box2
    return !(box1.east < box2.west ||
             box1.west > box2.east ||
             box1.north < box2.south ||
             box1.south > box2.north);
  }

  /// Check if airspace bounding box intersects with viewport
  bool _isInViewport(fm.LatLngBounds airspaceBounds, fm.LatLngBounds viewport) {
    return _boundingBoxesOverlap(airspaceBounds, viewport);
  }

  /// Calculate rough bounding box from geometry without creating LatLng objects
  /// This is a performance optimization to avoid expensive object creation
  fm.LatLngBounds? _calculateRoughBoundsFromGeometry(geo.Polygon polygon) {
    final exterior = polygon.exterior;
    if (exterior == null || exterior.positions.isEmpty) {
      return null;
    }

    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;

    for (final pos in exterior.positions) {
      minLat = math.min(minLat, pos.y);
      maxLat = math.max(maxLat, pos.y);
      minLon = math.min(minLon, pos.x);
      maxLon = math.max(maxLon, pos.x);
    }

    return fm.LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
  }

  /// Optimized version using ClipperData directly - no LatLng conversion
  List<_ClippedPolygonData> _subtractPolygonsFromSubjectOptimized({
    required ClipperData subjectData,
    required int subjectIndex,
    required List<ClipperData> clippingDataList,
    required List<int> clippingIndices,
    required AirspaceData airspaceData,
    required AirspaceStyle style,
  }) {
    final stopwatch = Stopwatch()..start();
    try {
      // PRE-EXTRACTION OPTIMIZATION: Extract all paths in one tight loop for better cache locality
      // This reduces memory jumps and improves CPU cache utilization

      // Pre-extract subject path once
      final subjectPath = subjectData.getPath(subjectIndex);
      if (subjectPath == null || subjectPath.isEmpty) {
        return [];
      }

      // Pre-extract all clipping paths in a single tight loop (better cache usage)
      // This avoids interleaving path extraction with other operations
      final clipPaths = List<clipper.Path64>.filled(clippingDataList.length, const []);
      int validPathCount = 0;

      for (int i = 0; i < clippingDataList.length; i++) {
        final path = clippingDataList[i].getPath(clippingIndices[i]);
        if (path != null && path.isNotEmpty) {
          clipPaths[validPathCount++] = path;
        }
      }

      // Trim to actual valid paths
      final actualClipPaths = validPathCount == clippingDataList.length
          ? clipPaths
          : clipPaths.sublist(0, validPathCount);

      // If no clipping polygons, convert subject to LatLng and return
      if (actualClipPaths.isEmpty) {
        final points = _clipperPathToLatLngList(subjectPath);
        return [_ClippedPolygonData(
          outerPoints: points,
          holes: [],
          airspaceData: airspaceData,
          style: style,
        )];
      }

      // Perform boolean difference operation with pre-extracted paths
      final subjectPaths = <clipper.Path64>[subjectPath];
      final solution = clipper.Clipper.difference(
        subject: subjectPaths,
        clip: actualClipPaths,
        fillRule: clipper.FillRule.nonZero,
      );

      // Convert results back to LatLng for rendering
      final List<_ClippedPolygonData> results = [];
      for (final resultPath in solution) {
        if (resultPath.isNotEmpty) {
          final points = _clipperPathToLatLngList(resultPath);
          if (points.length >= 3) { // Valid polygon needs at least 3 points
            results.add(_ClippedPolygonData(
              outerPoints: points,
              holes: [],
              airspaceData: airspaceData,
              style: style,
            ));
          }
        }
      }

      stopwatch.stop();

      // Only log very slow clipping operations (>50ms)
      if (stopwatch.elapsedMilliseconds > 50) {
        LoggingService.structuredLazy('POLYGON_CLIPPING_SLOW', () => {
          'optimized': true,
          'clipping_polygons': actualClipPaths.length,
          'result_polygons': results.length,
          'airspace_name': airspaceData.name,
          'time_ms': stopwatch.elapsedMilliseconds,
        });
      }

      return results;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to perform optimized polygon clipping', error, stackTrace);
      // Fallback: convert and return original
      final points = subjectData.toLatLngPolygons()[subjectIndex];
      return [_ClippedPolygonData(
        outerPoints: points,
        holes: [],
        airspaceData: airspaceData,
        style: style,
      )];
    }
  }

  // REMOVED: _subtractPolygonsFromSubject method - now always use optimized ClipperData path

  /// Optimized polygon clipping using ClipperData directly
  List<_ClippedPolygonData> _applyPolygonClippingOptimized(
    List<CachedAirspaceGeometry> geometries,
    List<({fm.Polygon polygon, AirspacePolygonData data})> polygonsWithAltitude,
    fm.LatLngBounds viewport,
  ) {

    final overallStopwatch = Stopwatch()..start();
    final setupStopwatch = Stopwatch()..start();

    final List<_ClippedPolygonData> clippedPolygons = [];

    // Track performance metrics
    int actualComparisons = 0;
    int theoreticalComparisons = 0;
    int totalClippingTimeMs = 0;
    int longestClippingTimeMs = 0;
    String longestClippingAirspace = '';
    int completelyClippedCount = 0;
    final List<String> completelyClippedNames = [];
    final Map<String, int> clippingTimeByType = {};
    int altitudeRejections = 0;
    int boundsRejections = 0;
    int actualClippingOperations = 0;
    int emptyClippingLists = 0;

    // OPTIMIZATION: Use ClippingBatch for better cache locality
    final batch = ClippingBatch(geometries.length);

    // Build batch with ClipperData and bounds
    for (int i = 0; i < geometries.length && i < polygonsWithAltitude.length; i++) {
      final geometry = geometries[i];
      final polygonData = polygonsWithAltitude[i];

      // Use cached bounds from geometry (avoids redundant calculation)
      final bounds = _getBoundsFromGeometry(geometry);

      batch.add(
        clipper: geometry.clipperData,
        polygonIndex: 0, // Assume single polygon per geometry for now
        altitude: polygonData.data.airspaceData.getLowerAltitudeInFeet(),
        boundsData: bounds,
        data: polygonData.data,
      );
    }

    // Sort by altitude (lowest first) for early exit
    // Create sorted index array instead of sorting the batch itself
    final sortedIndices = List<int>.generate(batch.count, (i) => i);
    sortedIndices.sort((a, b) => batch.altitudes[a].compareTo(batch.altitudes[b]));

    setupStopwatch.stop();

    // Calculate theoretical comparisons
    final n = batch.count;
    theoreticalComparisons = (n * (n - 1)) ~/ 2;


    // Process each visible polygon from lowest to highest altitude using sorted indices
    for (int sortedI = 0; sortedI < batch.count; sortedI++) {
      final i = sortedIndices[sortedI];  // Get actual index from sorted array
      final currentAltitude = batch.altitudes[i];
      // currentBounds extracted but not used
      final airspaceData = batch.airspaceData[i].airspaceData;

      // Get style for current airspace
      final style = getStyleForAirspace(airspaceData);

      // Collect clipping data
      final clippingDataList = <ClipperData>[];
      final clippingIndices = <int>[];
      final clippingAirspaceData = <AirspaceData>[];

      // Local comparison metrics removed - not used

      // Process all lower altitude airspaces (using sorted order)
      for (int sortedJ = 0; sortedJ < sortedI; sortedJ++) {
        final j = sortedIndices[sortedJ];
        // Local comparison tracking removed
        actualComparisons++;

        final lowerAltitude = batch.altitudes[j];

        // Early exit - all remaining polygons are at same or higher altitude
        if (lowerAltitude >= currentAltitude) {
          // Local altitude rejection tracking removed
          altitudeRejections++;
          break;
        }

        // Optimized bounds check using packed Float32List data
        if (!batch.boundsOverlap(i, j)) {
          // Local bounds rejection tracking removed
          boundsRejections++;
          continue;
        }

        // Add to clipping set - require ClipperData
        if (batch.clipperData[j] != null) {
          clippingDataList.add(batch.clipperData[j]!);
          clippingIndices.add(batch.polygonIndices[j]);
          clippingAirspaceData.add(batch.airspaceData[j].airspaceData);
        } else {
          LoggingService.error('ClipperData missing for lower airspace', null, null);
        }
      }

      // Track if we're doing actual clipping
      if (clippingDataList.isEmpty) {
        emptyClippingLists++;
      } else {
        actualClippingOperations++;
      }

      // Perform clipping operation with timing
      final clippingStopwatch = Stopwatch()..start();
      final List<_ClippedPolygonData> clippedResults;

      // Always use optimized ClipperData path
      if (batch.clipperData[i] != null) {
        if (clippingDataList.isNotEmpty) {
          // Perform clipping with ClipperData
          clippedResults = _subtractPolygonsFromSubjectOptimized(
            subjectData: batch.clipperData[i]!,
            subjectIndex: batch.polygonIndices[i],
            clippingDataList: clippingDataList,
            clippingIndices: clippingIndices,
            airspaceData: airspaceData,
            style: style,
          );
        } else {
          // No clipping needed - convert directly to result
          final points = batch.clipperData[i]!.toLatLngPolygons()[batch.polygonIndices[i]];
          clippedResults = [_ClippedPolygonData(
            outerPoints: points,
            holes: [],
            airspaceData: airspaceData,
            style: style,
          )];
        }
      } else {
        // This should not happen if we're always using ClipperData from DB
        LoggingService.error('Missing ClipperData for airspace', null, null);
        clippedResults = [];
      }
      clippingStopwatch.stop();

      // Track timing statistics
      final clippingTimeMs = clippingStopwatch.elapsedMilliseconds;
      totalClippingTimeMs += clippingTimeMs;
      if (clippingTimeMs > longestClippingTimeMs) {
        longestClippingTimeMs = clippingTimeMs;
        longestClippingAirspace = airspaceData.name;
      }

      // Aggregate by type
      final typeKey = airspaceData.type.abbreviation;
      clippingTimeByType[typeKey] = (clippingTimeByType[typeKey] ?? 0) + clippingTimeMs;

      // Track if completely clipped
      if (clippedResults.isEmpty && batch.clipperData[i] != null) {
        completelyClippedCount++;
        completelyClippedNames.add(airspaceData.name);
      }

      clippedPolygons.addAll(clippedResults);
    }

    overallStopwatch.stop();

    // Calculate comparison efficiency
    final double comparisonReduction = theoreticalComparisons > 0
        ? ((theoreticalComparisons - actualComparisons) / theoreticalComparisons * 100)
        : 0.0;


    // Log summary if any were completely clipped
    if (completelyClippedCount > 0) {
      LoggingService.info('[CLIPPING_SUMMARY] $completelyClippedCount airspaces completely clipped: ${completelyClippedNames.take(5).join(", ")}${completelyClippedCount > 5 ? " ..." : ""}');
    }

    LoggingService.info('[AIRSPACE] Clipped ${clippedPolygons.length} airspaces in ${totalClippingTimeMs}ms');

    return clippedPolygons;
  }

  // REMOVED: Non-optimized _applyPolygonClipping - always use optimized ClipperData path


  /// Convert clipped polygon data to flutter_map Polygons
  List<fm.Polygon> _convertClippedPolygonsToFlutterMap(
    List<_ClippedPolygonData> clippedPolygons,
    double opacity,
  ) {
    final List<fm.Polygon> flutterMapPolygons = [];

    for (final clippedData in clippedPolygons) {
      if (clippedData.outerPoints.length >= 3) {
        // Create flutter_map polygon with holes support
        final polygon = fm.Polygon(
          points: clippedData.outerPoints,
          holePointsList: clippedData.holes.isNotEmpty ? clippedData.holes : null,
          color: clippedData.style.fillColor,  // Use color directly from style (already has correct opacity)
          borderColor: clippedData.style.borderColor,
          borderStrokeWidth: clippedData.style.borderWidth,
          pattern: clippedData.style.pattern ?? fm.StrokePattern.solid(),
          // Disable hole borders for cleaner appearance
          disableHolesBorder: true,
        );

        flutterMapPolygons.add(polygon);
      }
    }


    return flutterMapPolygons;
  }


  // Cache management methods

  /// Get cache statistics
  Future<Map<String, dynamic>> getCacheStatistics() async {
    final stats = await _metadataCache.getStatistics();
    final metrics = _metadataCache.getPerformanceMetrics();

    // Get database version from disk cache
    final dbVersion = await AirspaceDiskCache.instance.getDatabaseVersion();

    // Calculate database size in MB
    final databaseSizeMb = stats.totalMemoryBytes / 1024 / 1024;

    // Get summary information about loaded countries and airspaces
    final countryService = AirspaceCountryService.instance;
    final selectedCountries = await countryService.getSelectedCountries();
    final countryMetadata = await countryService.getCountryMetadata();
    final loadedCountries = countryMetadata.keys.toList();

    return {
      'statistics': stats.toJson(),
      'performance': metrics,
      'summary': {
        'total_unique_airspaces': stats.totalGeometries,
        'database_size_mb': databaseSizeMb.toStringAsFixed(2),
        'database_version': dbVersion,
        'memory_saved_mb': (stats.memoryReductionPercent * stats.totalMemoryBytes / 100 / 1024 / 1024).toStringAsFixed(2),
        'compression_ratio': stats.averageCompressionRatio.toStringAsFixed(2),
        'cache_hit_rate': stats.cacheHitRate.toStringAsFixed(2),
        'loaded_countries': loadedCountries,
        'country_count': loadedCountries.length,
        'selected_countries': selectedCountries,
        'selected_country_count': selectedCountries.length,
      },
    };
  }

  /// Clear all cache
  Future<void> clearCache() async {
    await _metadataCache.clearAllCache();
    await _geometryCache.clearAllCache();
    await _performanceLogger.logPerformanceSummary();
    LoggingService.info('Cleared all airspace cache data');
  }

  /// Clean expired cache data
  Future<void> cleanExpiredCache() async {
    await _metadataCache.cleanExpiredData();
    LoggingService.info('Cleaned expired airspace cache data');
  }

  /// Log cache efficiency report
  Future<void> logCacheEfficiency() async {
    await _performanceLogger.logCacheEfficiency();
  }

  /// Process cached geometries directly to Flutter Map polygons without GeoJSON conversion
  Future<List<fm.Polygon>> _processGeometriesToPolygons(
    List<CachedAirspaceGeometry> geometries,
    double opacity,
    fm.LatLngBounds viewport,
    bool enableClipping,
  ) async {
    final polygons = <fm.Polygon>[];
    final identificationPolygons = <AirspacePolygonData>[];
    final allIdentificationPolygons = <AirspacePolygonData>[];
    final visibleIncludedTypes = <AirspaceType>{};

    // For clipping support - collect polygons with their data
    final polygonsWithData = <({fm.Polygon polygon, AirspacePolygonData data})>[];

    // SQL already handles filtering - no need for counters

    for (final geometry in geometries) {
      // Use cached AirspaceData from geometry (avoids redundant property parsing)
      final airspaceData = geometry.getAirspaceData();

      // Delay LatLng conversion until after clipping if enabled
      final List<LatLng> allPoints;
      if (enableClipping) {
        // For clipping, we'll convert after clipping operations are done
        // Just use empty points for now, will be filled during clipping
        allPoints = const [];
      } else {
        // No clipping - convert to LatLng immediately for direct display
        final polygons = geometry.clipperData.toLatLngPolygons();
        allPoints = polygons.isNotEmpty ? polygons.first : const [];
      }

      // Add to all identification polygons (for tooltip) - defer conversion
      // We'll use a placeholder and convert only when actually needed for identification
      final identificationPoints = enableClipping ? const <LatLng>[] : allPoints;

      allIdentificationPolygons.add(AirspacePolygonData(
        points: identificationPoints,
        airspaceData: airspaceData,
      ));

      // SQL already filtered by type, class, elevation, and viewport
      // No need to filter again - just track the visible type
      final airspaceType = airspaceData.type;

      // Add to visible types
      visibleIncludedTypes.add(airspaceType);

      // Add to identification polygons (for airspace detection)
      identificationPolygons.add(AirspacePolygonData(
        points: identificationPoints,
        airspaceData: airspaceData,
      ));

      // Use cached style from geometry (avoids redundant style computation)
      final style = geometry.getStyle(getStyleForAirspace);

      // Create polygon - if clipping enabled, points will be updated later
      final polygon = fm.Polygon(
        points: allPoints,
        borderStrokeWidth: style.borderWidth,
        borderColor: style.borderColor,
        color: style.fillColor,  // Use color directly from style (already has correct opacity)
        pattern: style.pattern ?? fm.StrokePattern.solid(),
        // Labels removed for cleaner visualization
      );

      // Store polygon with its data for clipping
      polygonsWithData.add((
        polygon: polygon,
        data: AirspacePolygonData(
          points: allPoints,
          airspaceData: airspaceData,
        ),
      ));
    }

    // Sort and clip polygons if enabled
    if (polygonsWithData.isNotEmpty) {
      // SQL already sorted by altitude when enableClipping is true
      if (!enableClipping) {
        // Only sort if SQL didn't already sort for us
        polygonsWithData.sort((a, b) {
          return a.data.airspaceData.getLowerAltitudeInFeet()
              .compareTo(b.data.airspaceData.getLowerAltitudeInFeet());
        });
      }

      if (enableClipping) {
        // Apply polygon clipping to remove overlapping areas
        final clippingStopwatch = Stopwatch()..start();

        // Use optimized clipping if any geometry has ClipperData
        final hasClipperData = geometries.any((g) => g.clipperData != null);
        final List<_ClippedPolygonData> clippedPolygons;

        // Always use optimized path with ClipperData
        clippedPolygons = _applyPolygonClippingOptimized(geometries, polygonsWithData, viewport);

        clippingStopwatch.stop();

        // Convert clipped polygons back to flutter_map format
        polygons.addAll(_convertClippedPolygonsToFlutterMap(clippedPolygons, opacity));

        LoggingService.structuredLazy('DIRECT_CLIPPING_PERFORMANCE', () => {
          'polygons_input': polygonsWithData.length,
          'polygons_output': polygons.length,
          'clipping_time_ms': clippingStopwatch.elapsedMilliseconds,
          'optimized': hasClipperData,
        });
      } else {
        // No clipping - just extract polygons in sorted order
        for (final item in polygonsWithData) {
          polygons.add(item.polygon);
        }
      }

      LoggingService.info('[AIRSPACE] Processed ${polygons.length} polygons${enableClipping ? " with clipping" : ""}');
    }

    // Update identification service with all polygons (including filtered)
    final boundsKey = '${viewport.west},${viewport.south},${viewport.east},${viewport.north}';
    AirspaceIdentificationService.instance.updateAirspacePolygons(allIdentificationPolygons, boundsKey);

    // Update visible types
    _currentVisibleTypes = visibleIncludedTypes;

    LoggingService.structuredLazy('DIRECT_POLYGON_PROCESSING', () => {
      'total_geometries': geometries.length,
      'polygons_rendered': polygons.length,
      'note': 'All filtering performed at SQL level',
    });

    return polygons;
  }

  /// Dispose resources
  void dispose() {
    _performanceLogger.dispose();
  }
}

/// Helper class for direct Int32 to Clipper2 conversion
class ClipperData {
  final Int32List coords;
  final Int32List offsets;
  static const double _coordPrecision = 10000000.0; // 10^7 for 1.11cm precision

  ClipperData(this.coords, this.offsets);

  /// Create ClipperData from LatLng polygons
  factory ClipperData.fromLatLngPolygons(List<List<LatLng>> polygons) {
    // Calculate total points and create offsets
    int totalPoints = 0;
    for (final polygon in polygons) {
      totalPoints += polygon.length;
    }

    final coords = Int32List(totalPoints * 2);
    final offsets = Int32List(polygons.length);

    int coordIdx = 0;
    int offsetIdx = 0;

    for (final polygon in polygons) {
      offsets[offsetIdx++] = coordIdx ~/ 2;
      for (final point in polygon) {
        coords[coordIdx++] = (point.longitude * _coordPrecision).round();
        coords[coordIdx++] = (point.latitude * _coordPrecision).round();
      }
    }

    return ClipperData(coords, offsets);
  }

  /// Create paths without intermediate LatLng objects
  List<clipper.Path64> toPaths() {
    final paths = <clipper.Path64>[];

    for (int i = 0; i < offsets.length; i++) {
      final startIdx = offsets[i] * 2;
      final endIdx = (i + 1 < offsets.length)
          ? offsets[i + 1] * 2
          : coords.length;

      // Pre-allocate path capacity for better performance
      final pathLength = (endIdx - startIdx) ~/ 2;
      final path = List<clipper.Point64>.filled(pathLength, clipper.Point64(0, 0));

      int pathIndex = 0;
      for (int j = startIdx; j < endIdx; j += 2) {
        // Direct Int32 to Point64 (auto-promotes to Int64)
        path[pathIndex++] = clipper.Point64(coords[j], coords[j + 1]);
      }

      paths.add(path);
    }

    return paths;
  }

  /// Get single polygon for subject
  clipper.Path64 getPath(int index) {
    final startIdx = offsets[index] * 2;
    final endIdx = (index + 1 < offsets.length)
        ? offsets[index + 1] * 2
        : coords.length;

    // Pre-allocate path with known size
    final pointCount = (endIdx - startIdx) ~/ 2;
    final path = List<clipper.Point64>.filled(pointCount, clipper.Point64(0, 0));

    int pointIndex = 0;
    for (int i = startIdx; i < endIdx; i += 2) {
      path[pointIndex++] = clipper.Point64(coords[i], coords[i + 1]);
    }
    return path;
  }

  /// Fill a pre-allocated path buffer to avoid allocations
  /// Returns the number of points filled, or -1 if index is invalid
  int getPathInto(int index, List<clipper.Point64> buffer) {
    if (index >= offsets.length) return -1;

    final startIdx = offsets[index] * 2;
    final endIdx = (index + 1 < offsets.length)
        ? offsets[index + 1] * 2
        : coords.length;

    final pointCount = (endIdx - startIdx) ~/ 2;

    // Ensure buffer is large enough
    if (buffer.length < pointCount) {
      // Fallback to regular allocation if buffer too small
      return -1;
    }

    // Fill buffer directly without allocation
    int pointIndex = 0;
    for (int i = startIdx; i < endIdx; i += 2) {
      buffer[pointIndex++] = clipper.Point64(coords[i], coords[i + 1]);
    }

    return pointCount;
  }

  /// Get the number of points in a polygon (useful for pre-allocating buffers)
  int getPathPointCount(int index) {
    if (index >= offsets.length) return 0;

    final startIdx = offsets[index];
    final endIdx = (index + 1 < offsets.length)
        ? offsets[index + 1]
        : coords.length ~/ 2;

    return endIdx - startIdx;
  }

  /// Convert to LatLng for display (only when needed)
  List<List<LatLng>> toLatLngPolygons() {
    // Pre-allocate list with known size
    final polygons = List<List<LatLng>>.filled(offsets.length, const []);

    for (int i = 0; i < offsets.length; i++) {
      final startIdx = offsets[i] * 2;
      final endIdx = (i + 1 < offsets.length)
          ? offsets[i + 1] * 2
          : coords.length;

      // Pre-allocate polygon with known size
      final pointCount = (endIdx - startIdx) ~/ 2;
      final polygon = List<LatLng>.filled(pointCount, const LatLng(0, 0));

      int pointIndex = 0;
      for (int j = startIdx; j < endIdx; j += 2) {
        polygon[pointIndex++] = LatLng(
          coords[j + 1] / _coordPrecision,  // lat
          coords[j] / _coordPrecision,       // lng
        );
      }
      polygons[i] = polygon;
    }

    return polygons;
  }
}