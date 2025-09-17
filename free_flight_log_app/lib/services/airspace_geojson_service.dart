import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geobase/geobase.dart' as geo;
import 'package:clipper2/clipper2.dart' as clipper;
import '../services/logging_service.dart';
import '../services/openaip_service.dart';
import '../services/airspace_identification_service.dart';
import '../data/models/airspace_enums.dart';

/// Data structure for airspace information
class AirspaceData {
  final String name;
  final AirspaceType type;
  final IcaoClass? icaoClass;
  final Map<String, dynamic>? upperLimit;
  final Map<String, dynamic>? lowerLimit;
  final String? country;

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
  });

  /// Convert lower altitude limit to feet for sorting purposes
  /// GND = 0, ft AMSL = direct value, FL = value × 100
  int getLowerAltitudeInFeet() {
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
    final referenceStr = reference.isNotEmpty ? ' $reference' : '';

    return '$valueStr$unit$referenceStr';
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

  // OpenAIP Core API configuration
  static const String _coreApiBase = 'https://api.core.openaip.net/api';
  static const int _defaultLimit = 500;
  static const Duration _requestTimeout = Duration(seconds: 30);

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
      // Very wide area - country level
      latRange = 10.0;
      lngRange = 15.0;
    } else if (zoom < 10) {
      // Regional level
      latRange = 5.0;
      lngRange = 7.0;
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

  /// Fetch airspace data from OpenAIP Core API with fallback to sample data
  Future<String> fetchAirspaceGeoJson(fm.LatLngBounds bounds) async {
    final stopwatch = Stopwatch()..start();
    final apiKey = await _openAipService.getApiKey();

    // Build API URL with optional API key as query parameter
    var url = '$_coreApiBase/airspaces'
        '?bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}'
        '&limit=$_defaultLimit';

    // Add API key as query parameter if available (common method)
    if (apiKey != null && apiKey.isNotEmpty) {
      url += '&apiKey=$apiKey';
    }

    // Simplified actionable log
    LoggingService.info('[AIRSPACE] Fetching from API for bounds: ${bounds.west.toStringAsFixed(2)},${bounds.south.toStringAsFixed(2)},${bounds.east.toStringAsFixed(2)},${bounds.north.toStringAsFixed(2)}');

    try {
      // Prepare headers with multiple authentication methods
      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'FreeFlightLog/1.0',
      };

      // OpenAIP 2024 simplified authentication - try query parameter method first
      // (No additional headers needed for this method)

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(_requestTimeout);

      stopwatch.stop();

      // Only log if there's an issue
      if (response.statusCode != 200) {
        LoggingService.error('[AIRSPACE] API returned status ${response.statusCode}', null, null);
      }

      if (response.statusCode == 200) {
        // Count airspaces for performance logging
        int airspaceCount = 0;
        try {
          final parsed = json.decode(response.body);
          if (parsed['features'] != null) {
            airspaceCount = (parsed['features'] as List).length;
          }
        } catch (e) {
          // Ignore parse errors for counting
        }

        LoggingService.performance(
          'Airspace API Fetch',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          'airspaces=$airspaceCount, cache_hit=false, bounds=${bounds.west},${bounds.south},${bounds.east},${bounds.north}'
        );

        // Convert OpenAIP format to standard GeoJSON
        return _convertToGeoJson(response.body);
      } else {
        LoggingService.performance(
          'Airspace API Fetch (Failed)',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          'status=${response.statusCode}, fallback_to_sample=true'
        );

        // For authentication errors or API failures, use sample data for demo purposes
        LoggingService.info('API failed with status ${response.statusCode}, using sample airspace data for demo');
        return _getSampleGeoJson(bounds);
      }

    } catch (error, stackTrace) {
      stopwatch.stop();

      LoggingService.performance(
        'Airspace API Fetch (Error)',
        Duration(milliseconds: stopwatch.elapsedMilliseconds),
        'error=true, fallback_to_sample=true'
      );

      LoggingService.error('Failed to fetch airspace data from OpenAIP, using sample data', error, stackTrace);
      // Return sample data instead of failing completely
      return _getSampleGeoJson(bounds);
    }
  }

  /// Get sample GeoJSON data for demonstration purposes
  String _getSampleGeoJson(fm.LatLngBounds bounds) {
    // Create sample airspaces around the Alps region (typical bounds: 45-47N, 5-9E)
    // This will show different airspace types for demo purposes
    final sampleGeoJson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[
              [6.1, 45.85], // SW
              [6.4, 45.85], // SE
              [6.4, 46.05], // NE
              [6.1, 46.05], // NW
              [6.1, 45.85], // Close polygon
            ]],
          },
          'properties': {
            'name': 'Chamonix CTR (Demo)',
            'type': 'CTR',
            'class': 'D',
            'upperLimit': {'value': 9500, 'unit': 'ft', 'reference': 'AMSL'},
            'lowerLimit': {'value': 0, 'unit': 'ft', 'reference': 'GND'},
            'country': 'FR',
          },
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[
              [6.0, 45.7], // SW
              [6.6, 45.7], // SE
              [6.6, 46.2], // NE
              [6.0, 46.2], // NW
              [6.0, 45.7], // Close polygon
            ]],
          },
          'properties': {
            'name': 'Geneva TMA (Demo)',
            'type': 'TMA',
            'class': 'C',
            'upperLimit': {'value': 19500, 'unit': 'ft', 'reference': 'AMSL'},
            'lowerLimit': {'value': 9500, 'unit': 'ft', 'reference': 'AMSL'},
            'country': 'CH',
          },
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[
              [6.5, 45.9], // SW
              [6.8, 45.9], // SE
              [6.8, 46.1], // NE
              [6.5, 46.1], // NW
              [6.5, 45.9], // Close polygon
            ]],
          },
          'properties': {
            'name': 'Restricted Area R-42 (Demo)',
            'type': 'R',
            'class': null,
            'upperLimit': {'value': 12000, 'unit': 'ft', 'reference': 'AMSL'},
            'lowerLimit': {'value': 0, 'unit': 'ft', 'reference': 'GND'},
            'country': 'FR',
          },
        },
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Polygon',
            'coordinates': [[
              [5.8, 45.6], // SW
              [6.2, 45.6], // SE
              [6.2, 45.9], // NE
              [5.8, 45.9], // NW
              [5.8, 45.6], // Close polygon
            ]],
          },
          'properties': {
            'name': 'Annecy CTA (Demo)',
            'type': 'CTA',
            'class': 'E',
            'upperLimit': {'value': 9500, 'unit': 'ft', 'reference': 'AMSL'},
            'lowerLimit': {'value': 4500, 'unit': 'ft', 'reference': 'AMSL'},
            'country': 'FR',
          },
        },
      ],
    };

    // Simple notification for demo mode
    LoggingService.info('[AIRSPACE] Using demo data with ${(sampleGeoJson['features'] as List).length} features');

    return json.encode(sampleGeoJson);
  }

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

    // Extract geometry
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
      // Use geobase to parse the GeoJSON data
      final featureCollection = geo.FeatureCollection.parse(geoJsonString);

      List<fm.Polygon> polygons = <fm.Polygon>[];
      List<AirspacePolygonData> identificationPolygons = <AirspacePolygonData>[];
      List<AirspacePolygonData> allIdentificationPolygons = <AirspacePolygonData>[]; // For tooltip - includes ALL airspaces
      final Set<AirspaceType> visibleIncludedTypes = <AirspaceType>{}; // Track visible included types

      // Filtering counters for summary logging
      int filteredByType = 0;
      int filteredByClass = 0;
      int filteredByElevation = 0;
      final Map<AirspaceType, int> filteredTypeDetails = {};
      final Map<IcaoClass, int> filteredClassDetails = {};

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

      // Sort polygons by lower altitude: highest first, lowest last
      // This ensures lowest airspaces render on top (most visible)
      if (polygons.isNotEmpty && identificationPolygons.isNotEmpty) {
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

        if (enableClipping) {
          // Apply polygon clipping to remove overlapping areas
          final clippedPolygons = _applyPolygonClipping(polygonsWithAltitude, viewport);

          // Convert clipped polygons back to flutter_map format
          polygons = _convertClippedPolygonsToFlutterMap(clippedPolygons, opacity);

          // For clipped polygons, keep original boundaries for tooltip hit testing
          identificationPolygons = polygonsWithAltitude.map((p) => p.data).toList();

          // Simple actionable log
          LoggingService.info('[AIRSPACE] Sorted ${polygonsWithAltitude.length} polygons by altitude for clipping');
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

      // Remove verbose result logging - already covered above

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
        color: style.fillColor.withValues(alpha: opacity),
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

  /// Coordinate conversion precision factor (10^7 for geographic coordinates)
  static const double _coordPrecision = 10000000.0;

  /// Convert LatLng to clipper2's integer coordinate system
  clipper.Point64 _latLngToClipper(LatLng point) {
    return clipper.Point64(
      (point.longitude * _coordPrecision).round(),
      (point.latitude * _coordPrecision).round(),
    );
  }

  /// Convert clipper2 integer coordinates back to LatLng
  LatLng _clipperToLatLng(clipper.Point64 point) {
    return LatLng(
      point.y / _coordPrecision,
      point.x / _coordPrecision,
    );
  }

  /// Convert List<LatLng> to clipper2 Path64
  clipper.Path64 _latLngListToClipperPath(List<LatLng> points) {
    final path = <clipper.Point64>[];
    for (final point in points) {
      path.add(_latLngToClipper(point));
    }
    return path;
  }

  /// Convert clipper2 Path64 to List<LatLng>
  List<LatLng> _clipperPathToLatLngList(clipper.Path64 path) {
    return path.map((point) => _clipperToLatLng(point)).toList();
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

  /// Subtract multiple polygons from a subject polygon using boolean difference
  /// Returns list of resulting polygons (may be empty, single, or multiple)
  List<_ClippedPolygonData> _subtractPolygonsFromSubject({
    required List<LatLng> subjectPoints,
    required List<List<LatLng>> clippingPolygons,
    required List<AirspaceData> clippingAirspaceData,
    required AirspaceData airspaceData,
    required AirspaceStyle style,
  }) {
    try {
      if (subjectPoints.isEmpty) {
        return [];
      }

      // Convert subject polygon to clipper format
      final subjectPath = _latLngListToClipperPath(subjectPoints);
      final subjectPaths = <clipper.Path64>[subjectPath];

      // Convert all clipping polygons to clipper format
      final clipPaths = <clipper.Path64>[];
      for (final clippingPoints in clippingPolygons) {
        if (clippingPoints.isNotEmpty) {
          clipPaths.add(_latLngListToClipperPath(clippingPoints));
        }
      }

      // If no clipping polygons, return original
      if (clipPaths.isEmpty) {
        return [_ClippedPolygonData(
          outerPoints: subjectPoints,
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

      // Convert results back to LatLng
      final List<_ClippedPolygonData> results = [];
      for (final resultPath in solution) {
        if (resultPath.isNotEmpty) {
          final points = _clipperPathToLatLngList(resultPath);
          if (points.length >= 3) { // Valid polygon needs at least 3 points
            results.add(_ClippedPolygonData(
              outerPoints: points,
              holes: [], // For now, we handle simple polygons
              airspaceData: airspaceData,
              style: style,
            ));
          }
        }
      }

      // Track completely clipped airspaces
      if (results.isEmpty && subjectPoints.isNotEmpty) {
        // Extract names of airspaces that caused the clipping
        final clippingNames = clippingAirspaceData.map((data) =>
          '${data.name} (${data.getLowerAltitudeInFeet()}-${data.getUpperAltitudeInFeet()}ft)'
        ).toList();

        LoggingService.warning('AIRSPACE_COMPLETELY_CLIPPED', {
          'name': airspaceData.name,
          'type': airspaceData.type,
          'lower_alt': airspaceData.getLowerAltitudeInFeet(),
          'upper_alt': airspaceData.getUpperAltitudeInFeet(),
          'original_points': subjectPoints.length,
          'clipped_by_count': clippingPolygons.length,
          'clipped_by_names': clippingNames.join(', '),
          'clipped_by_details': clippingNames,
        });
      }

      LoggingService.structured('POLYGON_CLIPPING_OPERATION', {
        'subject_points': subjectPoints.length,
        'clipping_polygons': clippingPolygons.length,
        'clipping_total_points': clippingPolygons.fold<int>(0, (sum, p) => sum + p.length),
        'result_polygons': results.length,
        'airspace_name': airspaceData.name,
      });

      return results;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to perform polygon clipping operation', error, stackTrace);
      // Return original polygon if clipping fails
      return [_ClippedPolygonData(
        outerPoints: subjectPoints,
        holes: [],
        airspaceData: airspaceData,
        style: style,
      )];
    }
  }

  /// Apply polygon clipping to eliminate overlapping airspace areas
  /// Each airspace shows only the areas not covered by lower-altitude airspaces
  List<_ClippedPolygonData> _applyPolygonClipping(
    List<({fm.Polygon polygon, AirspacePolygonData data})> polygonsWithAltitude,
    fm.LatLngBounds viewport,
  ) {
    final List<_ClippedPolygonData> clippedPolygons = [];
    int completelyClippedCount = 0;
    List<String> completelyClippedNames = [];

    LoggingService.structured('AIRSPACE_CLIPPING_START', {
      'input_polygons': polygonsWithAltitude.length,
    });

    // STAGE 1: Filter to viewport-visible airspaces only
    final List<({fm.Polygon polygon, AirspacePolygonData data, fm.LatLngBounds bounds})> visibleAirspaces = [];

    for (final polygon in polygonsWithAltitude) {
      final bounds = _calculateBoundingBox(polygon.data.points);
      if (_isInViewport(bounds, viewport)) {
        visibleAirspaces.add((
          polygon: polygon.polygon,
          data: polygon.data,
          bounds: bounds, // Pre-calculate for Stage 2
        ));
      }
    }

    LoggingService.structured('VIEWPORT_FILTERING', {
      'total_airspaces': polygonsWithAltitude.length,
      'visible_airspaces': visibleAirspaces.length,
      'filtered_out': polygonsWithAltitude.length - visibleAirspaces.length,
      'reduction_percent': polygonsWithAltitude.length > 0 ?
        ((polygonsWithAltitude.length - visibleAirspaces.length) / polygonsWithAltitude.length * 100).round() : 0,
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
      int skippedDueToBounds = 0;
      int totalComparisons = 0;

      for (int j = 0; j < i; j++) {
        final lowerAirspace = visibleAirspaces[j];
        totalComparisons++;

        // STAGE 2: Skip if bounding boxes don't overlap
        if (!_boundingBoxesOverlap(currentBounds, lowerAirspace.bounds)) {
          skippedDueToBounds++;
          continue;
        }

        final lowerAltitude = lowerAirspace.data.airspaceData.getLowerAltitudeInFeet();
        final currentAltitude = airspaceData.getLowerAltitudeInFeet();

        // Only clip against polygons that are actually lower
        if (lowerAltitude < currentAltitude) {
          clippingPolygons.add(lowerAirspace.data.points);
          clippingAirspaceData.add(lowerAirspace.data.airspaceData);
        }
      }

      // Perform clipping operation
      final clippedResults = _subtractPolygonsFromSubject(
        subjectPoints: currentPoints,
        clippingPolygons: clippingPolygons,
        clippingAirspaceData: clippingAirspaceData,
        airspaceData: airspaceData,
        style: style,
      );

      // Remove verbose per-airspace logging - will summarize at the end instead

      // Track if this airspace was completely clipped away
      if (clippedResults.isEmpty && currentPoints.isNotEmpty) {
        completelyClippedCount++;
        completelyClippedNames.add(airspaceData.name);
      }

      clippedPolygons.addAll(clippedResults);
    }

    // Simplified actionable log for Claude Code
    LoggingService.info('[AIRSPACE] Clipped ${clippedPolygons.length} airspaces for viewport');

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
          color: clippedData.style.fillColor.withValues(alpha: opacity),
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
}