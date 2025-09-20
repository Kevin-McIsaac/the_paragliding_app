import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geobase/geobase.dart' as geo;
import 'package:clipper2/clipper2.dart' as clipper;
import '../services/logging_service.dart';
import '../services/openaip_service.dart';
import '../services/airspace_identification_service.dart';
import '../services/airspace_metadata_cache.dart';
import '../services/airspace_geometry_cache.dart';
import '../services/airspace_disk_cache.dart';
import '../services/airspace_performance_logger.dart';
import '../data/models/airspace_cache_models.dart';
import '../data/models/airspace_enums.dart';
import '../utils/performance_monitor.dart';

/// Data structure for airspace information
class AirspaceData {
  final String name;
  final AirspaceType type;
  final IcaoClass? icaoClass;
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
    this.icaoClass,
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

  const AirspaceStyle({
    required this.fillColor,
    required this.borderColor,
    this.borderWidth = 1.5,
    this.isDotted = false,
  });
}

/// Result container for polygon creation
class _PolygonResult {
  final fm.Polygon polygon;
  final List<LatLng> points;

  _PolygonResult({required this.polygon, required this.points});
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

  final OpenAipService _openAipService = OpenAipService.instance;
  final AirspaceMetadataCache _metadataCache = AirspaceMetadataCache.instance;
  final AirspaceGeometryCache _geometryCache = AirspaceGeometryCache.instance;
  final AirspacePerformanceLogger _performanceLogger = AirspacePerformanceLogger.instance;

  // Country-based caching mode
  bool _useCountryMode = false; // Will be set based on whether countries are loaded

  // OpenAIP Core API configuration
  static const String _coreApiBase = 'https://api.core.openaip.net/api';
  static const int _defaultLimit = 1000; // Maximum allowed by OpenAIP API
  static const Duration _requestTimeout = Duration(seconds: 30);

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

  /// Enable or disable country mode (deprecated - now auto-detected)
  @Deprecated('Country mode is now automatically detected based on loaded countries')
  Future<void> setCountryMode(bool enabled) async {
    // No-op: mode is now automatically determined
  }

  /// Check if any countries are loaded
  Future<bool> hasLoadedCountries() async {
    final countries = await AirspaceDiskCache.instance.getCachedCountries();
    return countries.isNotEmpty;
  }

  /// Fetch airspace data as GeoJSON string (deprecated - use fetchAirspacePolygonsDirect)
  @Deprecated('Use fetchAirspacePolygonsDirect for better performance')
  Future<String> fetchAirspaceGeoJson(fm.LatLngBounds bounds) async {
    // Only support country mode now - tile mode removed
    final hasCountries = await hasLoadedCountries();
    if (!hasCountries) {
      LoggingService.warning('No countries loaded, returning empty GeoJSON');
      return '{"type":"FeatureCollection","features":[]}';
    }
    _useCountryMode = true;
    return _fetchAirspaceFromCountries(bounds);
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

    LoggingService.structured('DIRECT_POLYGON_FETCH', {
      'bounds': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      'max_altitude_ft': maxAltitudeFt,
      'clipping_enabled': enableClipping,
    });

    // Check if we have loaded countries
    final countries = await AirspaceDiskCache.instance.getCachedCountries();
    if (countries.isEmpty) {
      LoggingService.warning('No countries loaded for airspace display');
      return [];
    }

    // Convert excluded types to integer codes for SQL filtering
    final excludedTypeCodes = excludedTypes.map((type) => type.code).toSet();
    final excludedClassCodes = excludedClasses.map((cls) => cls.code).toSet();

    // Get airspaces with SQL-level filtering
    // Request ClipperData when clipping is enabled for optimal performance
    final geometries = await _metadataCache.getAirspacesForViewport(
      countryCodes: countries,
      west: bounds.west,
      south: bounds.south,
      east: bounds.east,
      north: bounds.north,
      excludedTypes: excludedTypeCodes,
      excludedClasses: excludedClassCodes,
      maxAltitudeFt: maxAltitudeFt,
      orderByAltitude: enableClipping, // Order by altitude when clipping is enabled
      useClipperData: enableClipping, // Use direct Int32 data for clipping
    );

    // Convert directly to Flutter Map polygons
    final processingStopwatch = Stopwatch()..start();
    final polygons = await _processGeometriesToPolygons(
      geometries,
      opacity,
      excludedTypes,
      excludedClasses,
      bounds,
      maxAltitudeFt,
      enableClipping,
    );
    processingStopwatch.stop();

    overallStopwatch.stop();
    final memoryAfter = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structured('DIRECT_POLYGON_COMPLETE', {
      'countries': countries.length,
      'total_ms': overallStopwatch.elapsedMilliseconds,
      'processing_ms': processingStopwatch.elapsedMilliseconds,
      'polygon_count': polygons.length,
      'memory_delta_mb': (memoryAfter - memoryBefore).toStringAsFixed(1),
    });

    return polygons;
  }

  /// Fetch airspace data from loaded countries
  Future<String> _fetchAirspaceFromCountries(fm.LatLngBounds bounds) async {
    final overallStopwatch = Stopwatch()..start();
    final memoryBefore = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structured('COUNTRY_MODE_FETCH', {
      'bounds': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
    });

    // Get list of loaded countries
    final countries = await AirspaceDiskCache.instance.getCachedCountries();
    if (countries.isEmpty) {
      LoggingService.warning('No countries loaded, returning empty GeoJSON');
      return '{"type":"FeatureCollection","features":[]}';
    }

    // Get airspaces for viewport from loaded countries
    final geometries = await _metadataCache.getAirspacesForViewport(
      countryCodes: countries,
      west: bounds.west,
      south: bounds.south,
      east: bounds.east,
      north: bounds.north,
    );

    // Build GeoJSON features from cached geometries
    final conversionStopwatch = Stopwatch()..start();
    final features = <Map<String, dynamic>>[];

    for (final geometry in geometries) {
      // Convert polygons to GeoJSON coordinates format
      // This path is for GeoJSON export, so we should have polygons
      if (geometry.polygons == null) {
        LoggingService.warning('Skipping geometry without polygons in GeoJSON conversion: ${geometry.id}');
        continue;
      }
      for (final polygon in geometry.polygons!) {
        if (polygon.isNotEmpty) {
          final coords = polygon.map((point) => [point.longitude, point.latitude]).toList();
          features.add({
            'type': 'Feature',
            'geometry': {
              'type': 'Polygon',
              'coordinates': [coords],
            },
            'properties': geometry.properties,
          });
        }
      }
    }
    conversionStopwatch.stop();

    final geoJson = {
      'type': 'FeatureCollection',
      'features': features,
    };

    final mergedGeoJson = json.encode(geoJson);

    overallStopwatch.stop();
    final memoryAfter = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structured('COUNTRY_MODE_COMPLETE', {
      'countries': countries.length,
      'total_ms': overallStopwatch.elapsedMilliseconds,
      'unique_airspaces': features.length,
      'conversion_ms': conversionStopwatch.elapsedMilliseconds,
      'memory_delta_mb': (memoryAfter - memoryBefore).toStringAsFixed(1),
    });

    LoggingService.performance(
      'Airspace Fetch (Country Mode)',
      overallStopwatch.elapsed,
      'countries=${countries.length}, airspaces=${features.length}',
    );

    return mergedGeoJson;
  }

  /// Fetch airspace data from OpenAIP Core API with hierarchical caching (tile mode)
  @Deprecated('Tile-based fetching is no longer supported - use country mode')
  Future<String> _fetchAirspaceFromTiles(fm.LatLngBounds bounds) async {
    // Tile-based fetching has been removed - only country mode is supported
    throw UnsupportedError('Tile-based fetching is no longer supported. Please download country data.');
  }

  // [REMOVED: All tile-based helper methods below - they are no longer used]

  /// Convert OpenAIP response format to standard GeoJSON
  String _convertToGeoJson(String responseBody) {
    try {
      final data = json.decode(responseBody);

      // Handle different response formats
      List<dynamic> items;
      if (data is Map<String, dynamic>) {
        items = data['items'] ?? data['features'] ?? [data];
      } else if (data is List) {
        items = data;
      } else {
        throw Exception('Unexpected response format');
      }

      // Build GeoJSON FeatureCollection
      final features = items.map((item) => _convertAirspaceToFeature(item)).toList();

      final geoJson = {
        'type': 'FeatureCollection',
        'features': features,
      };

      final result = json.encode(geoJson);

      LoggingService.structured('GEOJSON_CONVERSION', {
        'input_items': items.length,
        'output_features': features.length,
        'output_size': result.length,
      });

      // Log sample airspace data to understand OpenAIP structure
      if (items.isNotEmpty) {
        final sample = items.first;
        LoggingService.structured('OPENAIP_SAMPLE_AIRSPACE', {
          'type': sample['type'],
          'category': sample['category'],
          'name': sample['name'],
          'icaoClass': sample['icaoClass'],
          'activity': sample['activity'],
          'all_keys': sample.keys.toList(),
        });
      }

      return result;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to convert airspace data to GeoJSON', error, stackTrace);
      rethrow;
    }
  }

  /// OpenAIP unit codes to aviation units mapping
  static const Map<int, String> _openAipUnits = {
    1: 'ft',    // Feet
    2: 'm',     // Meters
    6: 'FL',    // Flight Level
  };

  /// OpenAIP reference datum codes to aviation references mapping
  static const Map<int, String> _openAipReferenceDatums = {
    0: 'GND',   // Ground/Surface
    1: 'AMSL',  // Above Mean Sea Level
    2: 'STD',   // Standard (Flight Level)
  };

  /// OpenAIP ICAO class codes to class letters mapping
  static const Map<int, String> _openAipIcaoClasses = {
    0: 'G',     // Class G
    1: 'F',     // Class F
    2: 'E',     // Class E
    3: 'D',     // Class D
    4: 'C',     // Class C
    5: 'B',     // Class B
    6: 'A',     // Class A
  };

  /// Convert OpenAIP numeric altitude limit to text format
  Map<String, dynamic>? _convertAltitudeLimit(Map<String, dynamic>? limit) {
    if (limit == null) return null;

    final value = limit['value'];
    final unitCode = limit['unit'];
    final referenceCode = limit['referenceDatum'];

    // Handle special values
    if (value == 0 && referenceCode == 0) {
      return {'value': 'GND', 'unit': '', 'reference': ''};
    }

    // Convert unit code to text
    String unit = _openAipUnits[unitCode] ?? 'ft';

    // Convert reference datum code to text
    String reference = _openAipReferenceDatums[referenceCode] ?? 'AMSL';

    // For flight levels, use standard format
    if (unit == 'FL' || reference == 'STD') {
      return {'value': value, 'unit': 'FL', 'reference': ''};
    }

    return {
      'value': value,
      'unit': unit,
      'reference': reference,
    };
  }

  /// Convert single airspace item to GeoJSON feature
  Map<String, dynamic> _convertAirspaceToFeature(dynamic item) {
    if (item is! Map<String, dynamic>) {
      throw Exception('Invalid airspace item format');
    }

    // If this is already a GeoJSON feature, extract properties from within
    if (item['type'] == 'Feature' && item.containsKey('properties')) {
      // Feature format from API - properties are nested
      final properties = item['properties'] as Map<String, dynamic>;
      final geometry = item['geometry'];

      if (geometry == null) {
        throw Exception('Airspace feature missing geometry');
      }

      // Properties are already in the right format, just ensure type is numeric
      final cleanedProps = <String, dynamic>{
        'name': properties['name'] ?? 'Unknown Airspace',
        'type': properties['type'] ?? 0,  // Keep numeric type code
        'class': properties['icaoClass'],  // Keep numeric ICAO class code
        'icaoClass': properties['icaoClass'],  // Also store with OpenAIP field name for compatibility
        'upperLimit': _convertAltitudeLimit(properties['upperLimit'] as Map<String, dynamic>?),
        'lowerLimit': _convertAltitudeLimit(properties['lowerLimit'] as Map<String, dynamic>?),
        'country': properties['country'],
      };

      return {
        'type': 'Feature',
        'geometry': geometry,
        'properties': cleanedProps,
      };
    }

    // Old format - properties at top level (shouldn't happen with OpenAIP)
    final geometry = item['geometry'];
    if (geometry == null) {
      throw Exception('Airspace missing geometry');
    }

    // Convert altitude limits from numeric codes to text
    final upperLimit = _convertAltitudeLimit(item['upperLimit'] as Map<String, dynamic>?);
    final lowerLimit = _convertAltitudeLimit(item['lowerLimit'] as Map<String, dynamic>?);

    // Extract properties - keep numeric codes
    final properties = <String, dynamic>{
      'name': item['name'] ?? 'Unknown Airspace',
      'type': item['type'] ?? 0,  // Keep numeric type code
      'class': item['icaoClass'],  // Keep numeric ICAO class code
      'icaoClass': item['icaoClass'],  // Also store with OpenAIP field name for compatibility
      'upperLimit': upperLimit,
      'lowerLimit': lowerLimit,
      'country': item['country'],
    };

    return {
      'type': 'Feature',
      'geometry': geometry,
      'properties': properties,
    };
  }

  /// Parse GeoJSON string and return styled polygons for flutter_map
  /// Also populates the AirspaceIdentificationService with polygon data
  /// Filters polygons based on user-excluded airspace types
  /// Optionally clips overlapping polygons for visual clarity
  Future<List<fm.Polygon>> parseAirspaceGeoJson(
    String geoJsonString,
    double opacity,
    Map<AirspaceType, bool> excludedTypes,
    Map<IcaoClass, bool> excludedIcaoClasses,
    fm.LatLngBounds viewport,
    double maxAltitudeFt,
    bool enableClipping,
  ) async {
    try {
      // Performance timing for each stage
      final totalStopwatch = Stopwatch()..start();
      final parsingStopwatch = Stopwatch()..start();

      // Use geobase to parse the GeoJSON data
      final featureCollection = geo.FeatureCollection.parse(geoJsonString);
      parsingStopwatch.stop();

      List<fm.Polygon> polygons = <fm.Polygon>[];
      List<AirspacePolygonData> identificationPolygons = <AirspacePolygonData>[];
      List<AirspacePolygonData> allIdentificationPolygons = <AirspacePolygonData>[]; // For tooltip - includes ALL airspaces
      final Set<AirspaceType> visibleIncludedTypes = <AirspaceType>{}; // Track visible included types

      // Filtering counters for summary logging
      int filteredByType = 0;
      int filteredByClass = 0;
      int filteredByElevation = 0;
      int filteredByViewport = 0;
      final Map<AirspaceType, int> filteredTypeDetails = {};
      final Map<IcaoClass, int> filteredClassDetails = {};

      // Start filtering and polygon creation timing
      final filteringStopwatch = Stopwatch()..start();

      for (final feature in featureCollection.features) {
        final geometry = feature.geometry;
        final properties = feature.properties;

        if (geometry != null) {
          // Create airspace data from properties
          final airspaceData = AirspaceData(
            name: properties != null ? properties['name']?.toString() ?? 'Unknown Airspace' : 'Unknown Airspace',
            type: AirspaceType.fromCode(properties != null ? (properties['type'] as int?) ?? 0 : 0),
            icaoClass: IcaoClass.fromCode(properties != null ? properties['class'] as int? : null),
            upperLimit: properties != null ? properties['upperLimit'] as Map<String, dynamic>? : null,
            lowerLimit: properties != null ? properties['lowerLimit'] as Map<String, dynamic>? : null,
            country: properties != null ? properties['country']?.toString() : null,
          );

          // Always add to identification polygons first (for tooltip - regardless of filters)
          if (geometry is geo.GeometryCollection) {
            // Handle geometry collections
            for (final geom in geometry.geometries) {
              final result = _createPolygonFromGeometry(geom, properties, opacity);
              if (result != null) {
                allIdentificationPolygons.add(AirspacePolygonData(
                  points: result.points,
                  airspaceData: airspaceData,
                ));
              }
            }
          } else {
            final result = _createPolygonFromGeometry(geometry, properties, opacity);
            if (result != null) {
              allIdentificationPolygons.add(AirspacePolygonData(
                points: result.points,
                airspaceData: airspaceData,
              ));
            }
          }

          // Filter based on excluded airspace types - skip only if explicitly excluded
          // This logic ensures unmapped types are shown by default
          if (excludedTypes[airspaceData.type] == true) {
            filteredByType++;
            filteredTypeDetails[airspaceData.type] = (filteredTypeDetails[airspaceData.type] ?? 0) + 1;
            continue; // Skip this airspace only if its type is explicitly excluded
          }

          // Filter based on excluded ICAO classes - skip only if explicitly excluded
          // Handle null ICAO class (treat as IcaoClass.none per OpenAIP spec)
          final icaoClassKey = airspaceData.icaoClass ?? IcaoClass.none;
          if (excludedIcaoClasses[icaoClassKey] == true) {
            filteredByClass++;
            filteredClassDetails[icaoClassKey] = (filteredClassDetails[icaoClassKey] ?? 0) + 1;
            continue; // Skip this airspace only if its ICAO class is explicitly excluded
          }

          // Filter based on maximum elevation setting
          // Skip airspaces that START above the elevation filter
          if (airspaceData.getLowerAltitudeInFeet() > maxAltitudeFt) {
            filteredByElevation++;
            continue; // Skip airspaces that start above the elevation filter
          }

          // Track this type as visible and included
          visibleIncludedTypes.add(airspaceData.type);

          // PERFORMANCE OPTIMIZATION: Check viewport bounds BEFORE creating polygon objects
          // Calculate rough bounds from geometry to avoid expensive polygon creation
          fm.LatLngBounds? roughBounds;

          if (geometry is geo.Polygon) {
            roughBounds = _calculateRoughBoundsFromGeometry(geometry);
          } else if (geometry is geo.MultiPolygon && geometry.polygons.isNotEmpty) {
            roughBounds = _calculateRoughBoundsFromGeometry(geometry.polygons.first);
          } else if (geometry is geo.GeometryCollection && geometry.geometries.isNotEmpty) {
            // For collections, check first geometry
            final firstGeom = geometry.geometries.first;
            if (firstGeom is geo.Polygon) {
              roughBounds = _calculateRoughBoundsFromGeometry(firstGeom);
            }
          }

          // Skip if completely outside viewport (early bounds check)
          if (roughBounds != null && !_isInViewport(roughBounds, viewport)) {
            filteredByViewport++;
            continue; // Skip this airspace - it's outside the viewport
          }

          // Handle different geometry types
          if (geometry is geo.GeometryCollection) {
            // Handle geometry collections
            for (final geom in geometry.geometries) {
              final result = _createPolygonFromGeometry(geom, properties, opacity);
              if (result != null) {
                polygons.add(result.polygon);
                identificationPolygons.add(AirspacePolygonData(
                  points: result.points,
                  airspaceData: airspaceData,
                ));
              }
            }
          } else {
            final result = _createPolygonFromGeometry(geometry, properties, opacity);
            if (result != null) {
              polygons.add(result.polygon);
              identificationPolygons.add(AirspacePolygonData(
                points: result.points,
                airspaceData: airspaceData,
              ));
            }
          }
        }
      }

      filteringStopwatch.stop();

      // Log early viewport filtering performance
      LoggingService.structured('VIEWPORT_PRE_FILTERING', {
        'total_features': featureCollection.features.length,
        'viewport_visible': polygons.length,
        'filtered_by_viewport': filteredByViewport,
        'filtered_out_early': featureCollection.features.length - polygons.length - filteredByType - filteredByClass - filteredByElevation,
        'viewport_bounds': '${viewport.south},${viewport.west},${viewport.north},${viewport.east}',
      });

      // Sort polygons by lower altitude: highest first, lowest last
      // This ensures lowest airspaces render on top (most visible)
      final sortingStopwatch = Stopwatch();
      if (polygons.isNotEmpty && identificationPolygons.isNotEmpty) {
        sortingStopwatch.start();

        // Create paired list of polygons with their altitude data
        final polygonsWithAltitude = <({fm.Polygon polygon, AirspacePolygonData data})>[];
        for (int i = 0; i < polygons.length; i++) {
          polygonsWithAltitude.add((
            polygon: polygons[i],
            data: identificationPolygons[i],
          ));
        }

        // Sort by lower altitude: lowest first (ascending order) for rendering and clipping
        polygonsWithAltitude.sort((a, b) {
          return a.data.airspaceData.getLowerAltitudeInFeet()
              .compareTo(b.data.airspaceData.getLowerAltitudeInFeet());
        });

        sortingStopwatch.stop();

        if (enableClipping) {
          // Clipping is not supported for GeoJSON path - use direct polygon fetch for clipping
          LoggingService.warning('Clipping requested but not available in GeoJSON path');
        } else {
          // No clipping - keep original polygons but maintain altitude-based rendering order
          // Polygons are already in the list from the filtering loop above
          // They are sorted by altitude, so lower altitude airspaces render first (bottom layer)
          // Higher altitude airspaces render last (top layer, most visible)

          // Simple actionable log
          LoggingService.info('[AIRSPACE] Sorted ${polygons.length} polygons by altitude');
        }

        // IMPORTANT: Keep polygon order from sorting (lowest altitude first)
        // Lower altitude airspaces render first (bottom layer)
        // Higher altitude airspaces render last (top layer, most visible)
        // Note: Removed reversal to show lowest altitude on top visually
      }

      // Update the identification service with polygon data (use ALL airspaces, not just filtered ones)
      final boundsKey = _generateBoundsKeyFromGeoJson(featureCollection);
      AirspaceIdentificationService.instance.updateAirspacePolygons(allIdentificationPolygons, boundsKey);

      // Log filtering summary if anything was filtered
      final totalFiltered = filteredByType + filteredByClass + filteredByElevation;
      if (totalFiltered > 0) {
        // Build a concise summary message
        final filterBreakdown = <String>[];
        if (filteredByType > 0) {
          final types = filteredTypeDetails.keys.map((t) => t.abbreviation).join(',');
          filterBreakdown.add('type=$filteredByType ($types)');
        }
        if (filteredByClass > 0) {
          final classes = filteredClassDetails.keys.map((c) => c.abbreviation).join(',');
          filterBreakdown.add('class=$filteredByClass ($classes)');
        }
        if (filteredByElevation > 0) {
          filterBreakdown.add('elevation=$filteredByElevation');
        }

        LoggingService.structured('AIRSPACE_FILTERING_SUMMARY', {
          'total_features': featureCollection.features.length,
          'total_filtered': totalFiltered,
          'filtered_by_type': filteredByType,
          'filtered_by_class': filteredByClass,
          'filtered_by_elevation': filteredByElevation,
          'remaining_polygons': polygons.length,
          'breakdown': filterBreakdown.join(', '),
        });
      }

      // Actionable filtering summary (existing summary for compatibility)
      final excludedTypeList = excludedTypes.keys.where((k) => excludedTypes[k] == true).map((k) => k.abbreviation).toList();
      final excludedClassList = excludedIcaoClasses.keys.where((k) => excludedIcaoClasses[k] == true).map((k) => k.abbreviation).toList();
      if (excludedTypeList.isNotEmpty || excludedClassList.isNotEmpty || maxAltitudeFt < double.infinity) {
        final filtered = featureCollection.features.length - polygons.length;
        String msg = '[AIRSPACE] Filtered $filtered of ${featureCollection.features.length} features';
        if (excludedClassList.isNotEmpty) msg += ' (excluded: ${excludedClassList.join(",")})';
        if (maxAltitudeFt < double.infinity) msg += ' (max alt: ${maxAltitudeFt.toInt()}ft)';
        LoggingService.info(msg);
      }

      LoggingService.structured('GEOJSON_PARSING', {
        'features_count': featureCollection.features.length,
        'polygons_created': polygons.length,
        'identification_polygons': identificationPolygons.length,
        'geojson_size': geoJsonString.length,
      });

      // Update visible types with only enabled types that are present
      _currentVisibleTypes = visibleIncludedTypes;

      // Add airspace statistics logging (for debugging)
      _logAirspaceStatistics(featureCollection);

      totalStopwatch.stop();

      // Log detailed performance breakdown
      LoggingService.structured('AIRSPACE_PARSING_PERFORMANCE', {
        'total_time_ms': totalStopwatch.elapsedMilliseconds,
        'parsing_time_ms': parsingStopwatch.elapsedMilliseconds,
        'filtering_time_ms': filteringStopwatch.elapsedMilliseconds,
        'sorting_time_ms': sortingStopwatch.elapsedMilliseconds,
        'features_count': featureCollection.features.length,
        'polygons_created': polygons.length,
        'filtered_by_type': filteredByType,
        'filtered_by_class': filteredByClass,
        'filtered_by_elevation': filteredByElevation,
        'filtered_by_viewport': filteredByViewport,
      });

      return polygons;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to parse airspace GeoJSON', error, stackTrace);
      rethrow;
    }
  }


  /// Create a flutter_map Polygon from a geobase geometry
  /// Returns both the styled polygon and the coordinate points for identification
  /// Log statistics about airspace types and distribution
  void _logAirspaceStatistics(geo.FeatureCollection featureCollection) {
    final Map<String, int> typeStats = {};
    final Map<String, int> originalTypeStats = {};
    final Set<int> visibleTypes = <int>{};
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;

    for (final feature in featureCollection.features) {
      final props = feature.properties;
      if (props != null) {
        // Count by mapped type
        final originalType = props['type']?.toString() ?? 'null';
        final typeValue = props['type'] as int? ?? 0;
        final airspaceType = AirspaceType.fromCode(typeValue);
        final mappedType = airspaceType.abbreviation;

        typeStats[mappedType] = (typeStats[mappedType] ?? 0) + 1;
        originalTypeStats[originalType] = (originalTypeStats[originalType] ?? 0) + 1;

        // Track visible types for legend filtering (use numeric type)
        final numericType = props['type'] as int? ?? 0;
        visibleTypes.add(numericType);

        // Calculate bounds for coverage area
        final geometry = feature.geometry;
        if (geometry is geo.Polygon) {
          for (final ring in geometry.rings) {
            for (final point in ring.positions) {
              minLat = math.min(minLat, point.y);
              maxLat = math.max(maxLat, point.y);
              minLon = math.min(minLon, point.x);
              maxLon = math.max(maxLon, point.x);
            }
          }
        }
      }
    }

    // Update the visible types for legend filtering (convert int to AirspaceType)
    _currentVisibleTypes = visibleTypes.map((type) => AirspaceType.fromCode(type)).toSet();

    // Statistics logging removed - not actionable for development
  }

  _PolygonResult? _createPolygonFromGeometry(geo.Geometry geometry, Map<String, dynamic>? properties, double opacity) {
    try {
      List<LatLng> points = [];
      final props = properties ?? <String, dynamic>{};

      if (geometry is geo.Polygon) {
        // Extract exterior ring coordinates
        final exterior = geometry.exterior;
        if (exterior != null) {
          points = exterior.positions.map((pos) => LatLng(pos.y, pos.x)).toList();
        }
      } else if (geometry is geo.MultiPolygon) {
        // For multi-polygons, use the first polygon's exterior ring
        if (geometry.polygons.isNotEmpty) {
          final firstPolygon = geometry.polygons.first;
          final exterior = firstPolygon.exterior;
          if (exterior != null) {
            points = exterior.positions.map((pos) => LatLng(pos.y, pos.x)).toList();
          }
        }
      } else {
        // Skip non-polygon geometries
        return null;
      }

      if (points.isEmpty) return null;

      // Get airspace style based on ICAO class first, then type
      final typeValue = props['type'] as int? ?? 0;
      final airspaceType = AirspaceType.fromCode(typeValue);
      final icaoClass = IcaoClass.fromCode(props['class'] as int?);

      final airspaceData = AirspaceData(
        name: props['name']?.toString() ?? 'Unknown',
        type: airspaceType,
        icaoClass: icaoClass,
      );

      final style = getStyleForAirspace(airspaceData);

      // Debug logging for development only (disabled in production)
      // Uncomment for debugging new airspace types
      /*
      LoggingService.structured('AIRSPACE_TYPE_DEBUG', {
        'name': props['name'] ?? 'unknown',
        'original_type': typeValue,
        'mapped_type': mappedType,
        'has_style': _airspaceStyles.containsKey(mappedType),
        'style_used': _airspaceStyles.containsKey(mappedType) ? mappedType : 'DEFAULT_GRAY',
      });
      */

      final polygon = fm.Polygon(
        points: points,
        color: style.fillColor,  // Use color directly from style (already has correct opacity)
        borderColor: style.borderColor,
        borderStrokeWidth: style.borderWidth,
      );

      return _PolygonResult(polygon: polygon, points: points);

    } catch (error, stackTrace) {
      LoggingService.error('Failed to create polygon from geometry', error, stackTrace);
      return null;
    }
  }

  /// Get default style for unknown airspace types
  AirspaceStyle _getDefaultStyle() {
    return const AirspaceStyle(
      fillColor: Color(0x20808080),
      borderColor: Color(0xFF808080),
      borderWidth: 1.0,
    );
  }

  /// OpenAIP numeric type codes to string mapping
  /// Based on OpenAIP API documentation and ICAO standards
  static const Map<int, String> _openAipTypeCodes = {
    0: 'CTA',   // Control Area/Centre (MELBOURNE CENTRE, PERTH CENTRE)
    1: 'A',     // Class A
    2: 'B',     // Class B
    3: 'C',     // Class C
    4: 'D',     // Class D (Danger)
    5: 'E',     // Class E
    6: 'F',     // Class F
    7: 'G',     // Class G
    8: 'CTR',   // Control Zone
    9: 'TMA',   // Terminal Control Area
    10: 'CTA',  // Control Area
    11: 'R',    // Restricted
    12: 'P',    // Prohibited
    13: 'CTR',  // ATZ (Aerodrome Traffic Zone) - similar to CTR
    14: 'D',    // Danger Area
    15: 'R',    // Military Restricted
    16: 'TMA',  // Approach Control
    17: 'CTR',  // Airport Control Zone
    18: 'R',    // Temporary Restricted
    19: 'P',    // Temporary Prohibited
    20: 'D',    // Temporary Danger
    21: 'TMA',  // Terminal Area
    22: 'CTA',  // Control Terminal Area
    23: 'CTA',  // Control Area Extension
    24: 'CTA',  // Control Area Sector
    25: 'CTA',  // Control Area Step
    26: 'CTA',  // Control Terminal Area (CTA A, CTA C1-C7)
  };

  /// Convert OpenAIP numeric type to our style key
  String _mapOpenAipTypeToStyle(dynamic typeValue) {
    if (typeValue is int) {
      return _openAipTypeCodes[typeValue] ?? 'UNKNOWN';
    } else if (typeValue is String) {
      // Handle string types directly
      return typeValue.toUpperCase();
    }
    return 'UNKNOWN';
  }

  /// Get style for airspace data (ICAO class takes priority, fallback to type)
  AirspaceStyle getStyleForAirspace(AirspaceData airspaceData) {
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

  /// Convert clipper2 Path64 to List<LatLng> for final display only
  List<LatLng> _clipperPathToLatLngList(clipper.Path64 path) {
    const double coordPrecision = 10000000.0;
    return path.map((point) => LatLng(
      point.y / coordPrecision,
      point.x / coordPrecision,
    )).toList();
  }

  /// Calculate bounding box for a list of LatLng points
  fm.LatLngBounds _calculateBoundingBox(List<LatLng> points) {
    if (points.isEmpty) {
      // Return a minimal bounding box if no points
      return fm.LatLngBounds(LatLng(0, 0), LatLng(0, 0));
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLon = points.first.longitude;
    double maxLon = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLon = math.min(minLon, point.longitude);
      maxLon = math.max(maxLon, point.longitude);
    }

    return fm.LatLngBounds(
      LatLng(minLat, minLon),
      LatLng(maxLat, maxLon),
    );
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
      // Get subject path directly from ClipperData
      final subjectPath = subjectData.getPath(subjectIndex);
      if (subjectPath == null || subjectPath.isEmpty) {
        return [];
      }
      final subjectPaths = <clipper.Path64>[subjectPath];

      // Get clipping paths directly from ClipperData
      final clipPaths = <clipper.Path64>[];
      for (int i = 0; i < clippingDataList.length; i++) {
        final path = clippingDataList[i].getPath(clippingIndices[i]);
        if (path != null && path.isNotEmpty) {
          clipPaths.add(path);
        }
      }

      // If no clipping polygons, convert subject to LatLng and return
      if (clipPaths.isEmpty) {
        final points = _clipperPathToLatLngList(subjectPath);
        return [_ClippedPolygonData(
          outerPoints: points,
          holes: [],
          airspaceData: airspaceData,
          style: style,
        )];
      }

      // Perform boolean difference operation
      final solution = clipper.Clipper.difference(
        subject: subjectPaths,
        clip: clipPaths,
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
        LoggingService.structured('POLYGON_CLIPPING_SLOW', {
          'optimized': true,
          'clipping_polygons': clipPaths.length,
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
    LoggingService.info('[AIRSPACE_CLIPPING_START] input_polygons=${polygonsWithAltitude.length} | strategy=Optimized ClipperData');

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

    // Pre-process visible airspaces with ClipperData and bounds
    final visibleAirspaces = <({
      ClipperData? clipperData,
      int polygonIndex,
      AirspacePolygonData data,
      fm.LatLngBounds bounds,
    })>[];

    // Build list with ClipperData or fallback points
    for (int i = 0; i < geometries.length && i < polygonsWithAltitude.length; i++) {
      final geometry = geometries[i];
      final polygonData = polygonsWithAltitude[i];

      // Calculate bounds for optimization
      final bounds = _calculateBoundingBox(polygonData.data.points);

      visibleAirspaces.add((
        clipperData: geometry.clipperData,
        polygonIndex: 0, // Assume single polygon per geometry for now
        data: polygonData.data,
        bounds: bounds,
      ));
    }

    // Sort by altitude (lowest first) for early exit
    visibleAirspaces.sort((a, b) {
      final altA = a.data.airspaceData.getLowerAltitudeInFeet();
      final altB = b.data.airspaceData.getLowerAltitudeInFeet();
      return altA.compareTo(altB);
    });

    setupStopwatch.stop();

    // Pre-extract altitude array for cache locality
    final List<int> altitudeArray = List<int>.generate(
      visibleAirspaces.length,
      (i) => visibleAirspaces[i].data.airspaceData.getLowerAltitudeInFeet(),
      growable: false,
    );

    // Calculate theoretical comparisons
    final n = visibleAirspaces.length;
    theoreticalComparisons = (n * (n - 1)) ~/ 2;

    LoggingService.structured('CLIPPING_STAGE', {
      'input_polygons': polygonsWithAltitude.length,
      'polygons_to_clip': visibleAirspaces.length,
      'theoretical_comparisons': theoreticalComparisons,
      'setup_time_ms': setupStopwatch.elapsedMilliseconds,
      'optimized': true,
      'using_clipper_data': visibleAirspaces.any((v) => v.clipperData != null),
    });

    // Process each visible polygon from lowest to highest altitude
    for (int i = 0; i < visibleAirspaces.length; i++) {
      final current = visibleAirspaces[i];
      final currentBounds = current.bounds;
      final airspaceData = current.data.airspaceData;

      // Get style for current airspace
      final style = getStyleForAirspace(airspaceData);

      // Collect clipping data
      final clippingDataList = <ClipperData>[];
      final clippingIndices = <int>[];
      final clippingAirspaceData = <AirspaceData>[];

      // Local comparison metrics
      int localComparisons = 0;
      int localAltitudeRejections = 0;
      int localBoundsRejections = 0;

      final currentAltitude = altitudeArray[i];

      for (int j = 0; j < i; j++) {
        final lowerAirspace = visibleAirspaces[j];
        localComparisons++;
        actualComparisons++;

        final lowerAltitude = altitudeArray[j];

        // Early exit - all remaining polygons are at same or higher altitude
        if (lowerAltitude >= currentAltitude) {
          localAltitudeRejections++;
          altitudeRejections++;
          break;
        }

        // Inline bounding box check
        final lowerBounds = lowerAirspace.bounds;
        if (currentBounds.east < lowerBounds.west ||
            currentBounds.west > lowerBounds.east ||
            currentBounds.north < lowerBounds.south ||
            currentBounds.south > lowerBounds.north) {
          localBoundsRejections++;
          boundsRejections++;
          continue;
        }

        // Add to clipping set - require ClipperData
        if (lowerAirspace.clipperData != null) {
          clippingDataList.add(lowerAirspace.clipperData!);
          clippingIndices.add(lowerAirspace.polygonIndex);
          clippingAirspaceData.add(lowerAirspace.data.airspaceData);
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
      if (current.clipperData != null) {
        if (clippingDataList.isNotEmpty) {
          // Perform clipping with ClipperData
          clippedResults = _subtractPolygonsFromSubjectOptimized(
            subjectData: current.clipperData!,
            subjectIndex: current.polygonIndex,
            clippingDataList: clippingDataList,
            clippingIndices: clippingIndices,
            airspaceData: airspaceData,
            style: style,
          );
        } else {
          // No clipping needed - convert directly to result
          final points = current.clipperData!.toLatLngPolygons()[current.polygonIndex];
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
      if (clippedResults.isEmpty && current.data.points.isNotEmpty) {
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

    // Log detailed performance
    LoggingService.structured('CLIPPING_DETAILED_PERFORMANCE', {
      'strategy': 'Optimized ClipperData',
      'total_clipping_time_ms': totalClippingTimeMs,
      'overall_time_ms': overallStopwatch.elapsedMilliseconds,
      'setup_time_ms': setupStopwatch.elapsedMilliseconds,
      'average_time_ms': visibleAirspaces.isNotEmpty ? (totalClippingTimeMs / visibleAirspaces.length).round() : 0,
      'longest_time_ms': longestClippingTimeMs,
      'longest_airspace': longestClippingAirspace,
      'completely_clipped': completelyClippedCount,
      'time_by_type': clippingTimeByType,
      'total_comparisons': actualComparisons,
      'theoretical_comparisons': theoreticalComparisons,
      'comparison_reduction_%': comparisonReduction.toStringAsFixed(1),
      'altitude_rejections': altitudeRejections,
      'bounds_rejections': boundsRejections,
      'actual_clipping_operations': actualClippingOperations,
      'empty_clipping_lists': emptyClippingLists,
      'using_clipper_data': visibleAirspaces.any((v) => v.clipperData != null),
    });

    // Log summary if any were completely clipped
    if (completelyClippedCount > 0) {
      LoggingService.info('[CLIPPING_SUMMARY] $completelyClippedCount airspaces completely clipped: ${completelyClippedNames.take(5).join(", ")}${completelyClippedCount > 5 ? " ..." : ""}');
    }

    LoggingService.info('[AIRSPACE] Clipped ${clippedPolygons.length} airspaces in ${totalClippingTimeMs}ms');

    return clippedPolygons;
  }

  // REMOVED: Non-optimized _applyPolygonClipping - always use optimized ClipperData path

  /// Legacy polygon clipping method (kept for reference but not used)
  List<_ClippedPolygonData> _applyPolygonClippingLegacy(
    List<({fm.Polygon polygon, AirspacePolygonData data})> polygonsWithAltitude,
    fm.LatLngBounds viewport,
  ) {
    final List<_ClippedPolygonData> clippedPolygons = [];
    int completelyClippedCount = 0;
    List<String> completelyClippedNames = [];

    // Track timing for clipping operations
    int totalClippingTimeMs = 0;
    int longestClippingTimeMs = 0;
    String? longestClippingAirspace;
    final Map<String, int> clippingTimeByType = {};

    // Enhanced metrics for optimization tracking
    int theoreticalComparisons = 0;
    int actualComparisons = 0;
    int altitudeRejections = 0;
    int boundsRejections = 0;
    int actualClippingOperations = 0;
    int emptyClippingLists = 0;
    final setupStopwatch = Stopwatch()..start();

    final clippingMemoryBefore = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structured('AIRSPACE_CLIPPING_START', {
      'input_polygons': polygonsWithAltitude.length,
      'strategy': 'Linear O(n²)',
    });

    // STAGE 1: Viewport filtering already done in parseAirspaceGeoJson
    // All polygons passed here are already within viewport bounds
    // Just add bounds for overlap checking
    final List<({fm.Polygon polygon, AirspacePolygonData data, fm.LatLngBounds bounds})> visibleAirspaces = [];

    for (final polygon in polygonsWithAltitude) {
      final bounds = _calculateBoundingBox(polygon.data.points);
      visibleAirspaces.add((
        polygon: polygon.polygon,
        data: polygon.data,
        bounds: bounds, // Pre-calculate for Stage 2
      ));
    }

    // OPTIMIZATION: Sort by altitude (lowest first) for early exit
    final sortStopwatch = Stopwatch()..start();
    visibleAirspaces.sort((a, b) {
      final altA = a.data.airspaceData.getLowerAltitudeInFeet();
      final altB = b.data.airspaceData.getLowerAltitudeInFeet();
      return altA.compareTo(altB);
    });
    sortStopwatch.stop();

    setupStopwatch.stop();

    // STAGE 3 OPTIMIZATION: Pre-extract frequently accessed data for better cache locality
    // Accessing data from contiguous arrays is faster than following object references
    final List<int> altitudeArray = List<int>.generate(
      visibleAirspaces.length,
      (i) => visibleAirspaces[i].data.airspaceData.getLowerAltitudeInFeet(),
      growable: false,
    );

    // Calculate theoretical comparisons (n*(n-1)/2)
    final n = visibleAirspaces.length;
    theoreticalComparisons = (n * (n - 1)) ~/ 2;

    LoggingService.structured('CLIPPING_STAGE', {
      'input_polygons': polygonsWithAltitude.length,
      'polygons_to_clip': visibleAirspaces.length,
      'theoretical_comparisons': theoreticalComparisons,
      'setup_time_ms': setupStopwatch.elapsedMilliseconds,
      'sort_time_ms': sortStopwatch.elapsedMilliseconds,
      'sorted_by_altitude': true,
      'stage_3_cache_optimized': true,
    });

    // Process each visible polygon from lowest to highest altitude
    for (int i = 0; i < visibleAirspaces.length; i++) {
      final current = visibleAirspaces[i];
      final currentPoints = current.data.points;
      final airspaceData = current.data.airspaceData;
      final currentBounds = current.bounds; // Pre-calculated

      // Get style for current airspace (prioritizes ICAO class)
      final style = getStyleForAirspace(airspaceData);

      // Collect all lower-altitude polygons as clipping masks
      final List<List<LatLng>> clippingPolygons = [];
      final List<AirspaceData> clippingAirspaceData = [];

      // Local comparison metrics
      int localComparisons = 0;
      int localAltitudeRejections = 0;
      int localBoundsRejections = 0;
      int earlyExitSavings = 0;

      // STAGE 3: Use pre-extracted altitude from array (better cache locality)
      final currentAltitude = altitudeArray[i];

      for (int j = 0; j < i; j++) {
        final lowerAirspace = visibleAirspaces[j];
        localComparisons++;
        actualComparisons++;

        // STAGE 3 OPTIMIZATION: Access altitude from contiguous array (cache-friendly)
        final lowerAltitude = altitudeArray[j];

        // Early exit - all remaining polygons are at same or higher altitude
        if (lowerAltitude >= currentAltitude) {
          // Count how many comparisons we're saving
          earlyExitSavings = i - j - 1;
          actualComparisons -= earlyExitSavings; // Adjust for saved comparisons
          localAltitudeRejections++;
          altitudeRejections++;
          break; // EARLY EXIT - no need to check remaining polygons
        }

        // STAGE 2 OPTIMIZATION: Inline bounding box check (avoid function call overhead)
        // Direct comparison is faster than function call
        final lowerBounds = lowerAirspace.bounds;
        if (currentBounds.east < lowerBounds.west ||
            currentBounds.west > lowerBounds.east ||
            currentBounds.north < lowerBounds.south ||
            currentBounds.south > lowerBounds.north) {
          localBoundsRejections++;
          boundsRejections++;
          continue;
        }

        clippingPolygons.add(lowerAirspace.data.points);
        clippingAirspaceData.add(lowerAirspace.data.airspaceData);
      }

      // Track if we're doing actual clipping
      if (clippingPolygons.isEmpty) {
        emptyClippingLists++;
      } else {
        actualClippingOperations++;
      }

      // Perform clipping operation with timing
      final clippingStopwatch = Stopwatch()..start();
      // Legacy method no longer used - we always use ClipperData now
      final List<_ClippedPolygonData> clippedResults = [];
      // final clippedResults = _subtractPolygonsFromSubject(...);
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

      // Remove verbose per-airspace logging - will summarize at the end instead

      // Track if this airspace was completely clipped away
      if (clippedResults.isEmpty && currentPoints.isNotEmpty) {
        completelyClippedCount++;
        completelyClippedNames.add(airspaceData.name);
      }

      clippedPolygons.addAll(clippedResults);
    }

    // Calculate comparison efficiency
    final double comparisonReduction = theoreticalComparisons > 0
        ? ((theoreticalComparisons - actualComparisons) / theoreticalComparisons * 100)
        : 0.0;

    // Log detailed clipping performance with enhanced metrics
    LoggingService.structured('CLIPPING_DETAILED_PERFORMANCE', {
      'strategy': 'Linear O(n²) Search',
      'total_clipping_time_ms': totalClippingTimeMs,
      'overall_time_ms': setupStopwatch.elapsedMilliseconds + totalClippingTimeMs,
      'setup_time_ms': setupStopwatch.elapsedMilliseconds,
      'average_time_ms': visibleAirspaces.isNotEmpty ? (totalClippingTimeMs / visibleAirspaces.length).round() : 0,
      'longest_time_ms': longestClippingTimeMs,
      'longest_airspace': longestClippingAirspace,
      'completely_clipped': completelyClippedCount,
      'time_by_type': clippingTimeByType,
      'total_comparisons': actualComparisons,
      'theoretical_comparisons': theoreticalComparisons,
      'comparison_reduction_%': comparisonReduction.toStringAsFixed(1),
      'altitude_rejections': altitudeRejections,
      'bounds_rejections': boundsRejections,
      'actual_clipping_operations': actualClippingOperations,
      'empty_clipping_lists': emptyClippingLists,
    });

    // Log summary of completely clipped airspaces if any
    if (completelyClippedCount > 0) {
      LoggingService.info('[CLIPPING_SUMMARY] $completelyClippedCount airspaces completely clipped: ${completelyClippedNames.take(5).join(", ")}${completelyClippedCount > 5 ? " ..." : ""}');
    }

    // Simplified actionable log for Claude Code
    LoggingService.info('[AIRSPACE] Clipped ${clippedPolygons.length} airspaces in ${totalClippingTimeMs}ms');

    // Log memory usage for clipping operation
    final clippingMemoryAfter = PerformanceMonitor.getMemoryUsageMB();
    LoggingService.structured('MEMORY_USAGE', {
      'operation': 'polygon_clipping',
      'before_mb': clippingMemoryBefore.toStringAsFixed(1),
      'after_mb': clippingMemoryAfter.toStringAsFixed(1),
      'delta_mb': (clippingMemoryAfter - clippingMemoryBefore).toStringAsFixed(1),
      'polygons_clipped': clippedPolygons.length,
      'input_polygons': polygonsWithAltitude.length,
    });

    return clippedPolygons;
  }

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
          // Disable hole borders for cleaner appearance
          disableHolesBorder: true,
        );

        flutterMapPolygons.add(polygon);
      }
    }

    LoggingService.structured('CLIPPED_POLYGONS_CONVERSION', {
      'clipped_polygons_input': clippedPolygons.length,
      'flutter_map_polygons_output': flutterMapPolygons.length,
      'polygons_with_holes': clippedPolygons.where((p) => p.holes.isNotEmpty).length,
    });

    return flutterMapPolygons;
  }

  /// Generate bounds key from GeoJSON feature collection
  String _generateBoundsKeyFromGeoJson(geo.FeatureCollection featureCollection) {
    if (featureCollection.features.isEmpty) return 'empty';

    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;

    for (final feature in featureCollection.features) {
      final geometry = feature.geometry;
      if (geometry is geo.Polygon) {
        for (final ring in geometry.rings) {
          for (final point in ring.positions) {
            minLat = math.min(minLat, point.y);
            maxLat = math.max(maxLat, point.y);
            minLon = math.min(minLon, point.x);
            maxLon = math.max(maxLon, point.x);
          }
        }
      }
    }

    return '${minLat.toStringAsFixed(2)},${minLon.toStringAsFixed(2)},${maxLat.toStringAsFixed(2)},${maxLon.toStringAsFixed(2)}';
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

    return {
      'statistics': stats.toJson(),
      'performance': metrics,
      'summary': {
        'total_unique_airspaces': stats.totalGeometries,
        'total_tiles_cached': stats.totalTiles,
        'empty_tiles': stats.emptyTiles,
        'database_size_mb': databaseSizeMb.toStringAsFixed(2),
        'database_version': dbVersion,
        'memory_saved_mb': (stats.memoryReductionPercent * stats.totalMemoryBytes / 100 / 1024 / 1024).toStringAsFixed(2),
        'compression_ratio': stats.averageCompressionRatio.toStringAsFixed(2),
        'cache_hit_rate': stats.cacheHitRate.toStringAsFixed(2),
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
    Set<AirspaceType> excludedTypes,
    Set<IcaoClass> excludedClasses,
    fm.LatLngBounds viewport,
    double maxAltitudeFt,
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
      // Extract properties
      final properties = geometry.properties;

      // Debug log properties for first geometry
      if (geometries.indexOf(geometry) == 0) {
        LoggingService.structured('GEOMETRY_PROPERTIES_DEBUG', {
          'name': geometry.name,
          'type_code': geometry.typeCode,
          'properties_keys': properties.keys.toList(),
          'properties': properties,
        });
      }

      // Try both 'class' and 'icaoClass' field names for compatibility
      final icaoClass = (properties['class'] ?? properties['icaoClass']) as int?;
      final upperLimit = properties['upperLimit'] as Map<String, dynamic>?;
      final lowerLimit = properties['lowerLimit'] as Map<String, dynamic>?;
      final country = properties['country'] as String?;

      // Create airspace data from geometry metadata
      final airspaceData = AirspaceData(
        name: geometry.name,
        type: AirspaceType.fromCode(geometry.typeCode),
        icaoClass: icaoClass != null ? IcaoClass.fromCode(icaoClass) : null,
        upperLimit: upperLimit,
        lowerLimit: lowerLimit,
        country: country,
        lowerAltitudeFt: geometry.lowerAltitudeFt,  // Use pre-computed altitude
      );

      // Process all polygon parts - handle both LatLng polygons and ClipperData
      final allPoints = <LatLng>[];
      if (geometry.clipperData != null) {
        // When using ClipperData, convert to LatLng only for display
        // The actual clipping will use the ClipperData directly
        final polygons = geometry.clipperData!.toLatLngPolygons();
        if (polygons.isNotEmpty) {
          allPoints.addAll(polygons.first);
        }
      } else if (geometry.polygons != null) {
        // Traditional path with LatLng polygons
        for (final polygon in geometry.polygons!) {
          if (polygon.isNotEmpty) {
            allPoints.addAll(polygon);
            // Just use first polygon for now (TODO: handle multi-polygon properly)
            break;
          }
        }
      }

      // Add to all identification polygons (for tooltip)
      allIdentificationPolygons.add(AirspacePolygonData(
        points: allPoints,
        airspaceData: airspaceData,
      ));

      // SQL already filtered by type, class, elevation, and viewport
      // No need to filter again - just track the visible type
      final airspaceType = AirspaceType.fromCode(geometry.typeCode);

      // Add to visible types
      visibleIncludedTypes.add(airspaceType);

      // Add to identification polygons (for airspace detection)
      identificationPolygons.add(AirspacePolygonData(
        points: allPoints,
        airspaceData: airspaceData,
      ));

      // Create Flutter Map polygon with styling
      // Use ICAO class-based styling first, then fall back to type-based styling
      final style = getStyleForAirspace(airspaceData);

      // Debug logging for first polygon only
      if (polygonsWithData.isEmpty) {
        LoggingService.structured('POLYGON_OPACITY_DEBUG', {
          'style_fill_color': style.fillColor.toString(),
          'style_border_color': style.borderColor.toString(),
          'airspace_type': airspaceType.toString(),
          'icao_class': airspaceData.icaoClass?.toString() ?? 'none',
          'using_icao_style': airspaceData.icaoClass != null,
        });
      }

      final polygon = fm.Polygon(
        points: allPoints,
        borderStrokeWidth: style.borderWidth,
        borderColor: style.borderColor,
        color: style.fillColor,  // Use color directly from style (already has correct opacity)
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

        LoggingService.structured('DIRECT_CLIPPING_PERFORMANCE', {
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

    LoggingService.structured('DIRECT_POLYGON_FILTERING', {
      'total_geometries': geometries.length,
      'filtered_by_type': 0,  // Filtering now done in SQL
      'filtered_by_class': 0,  // Filtering now done in SQL
      'filtered_by_elevation': 0,  // Filtering now done in SQL
      'filtered_by_viewport': 0,  // Filtering now done in SQL
      'polygons_rendered': polygons.length,
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

    final path = <clipper.Point64>[];
    for (int i = startIdx; i < endIdx; i += 2) {
      path.add(clipper.Point64(coords[i], coords[i + 1]));
    }
    return path;
  }

  /// Convert to LatLng for display (only when needed)
  List<List<LatLng>> toLatLngPolygons() {
    final polygons = <List<LatLng>>[];

    for (int i = 0; i < offsets.length; i++) {
      final startIdx = offsets[i] * 2;
      final endIdx = (i + 1 < offsets.length)
          ? offsets[i + 1] * 2
          : coords.length;

      final polygon = <LatLng>[];
      for (int j = startIdx; j < endIdx; j += 2) {
        polygon.add(LatLng(
          coords[j + 1] / _coordPrecision,  // lat
          coords[j] / _coordPrecision,       // lng
        ));
      }
      polygons.add(polygon);
    }

    return polygons;
  }
}