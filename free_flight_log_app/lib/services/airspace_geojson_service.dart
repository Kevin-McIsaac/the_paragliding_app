import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geobase/geobase.dart' as geo;
import '../services/logging_service.dart';
import '../services/openaip_service.dart';

/// Data structure for airspace information
class AirspaceData {
  final String name;
  final String type;
  final String? class_;
  final Map<String, dynamic>? upperLimit;
  final Map<String, dynamic>? lowerLimit;
  final String? country;

  AirspaceData({
    required this.name,
    required this.type,
    this.class_,
    this.upperLimit,
    this.lowerLimit,
    this.country,
  });

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

  // Airspace type to style mapping
  static const Map<String, AirspaceStyle> _airspaceStyles = {
    'CTR': AirspaceStyle(
      fillColor: Color(0x30FF0000),
      borderColor: Color(0xFFFF0000),
      borderWidth: 2.0,
    ),
    'TMA': AirspaceStyle(
      fillColor: Color(0x30FFA500),
      borderColor: Color(0xFFFFA500),
      borderWidth: 1.8,
    ),
    'CTA': AirspaceStyle(
      fillColor: Color(0x300000FF),
      borderColor: Color(0xFF0000FF),
      borderWidth: 1.5,
    ),
    'D': AirspaceStyle( // Danger
      fillColor: Color(0x40FF0000),
      borderColor: Color(0xFFFF0000),
      borderWidth: 2.0,
      isDotted: true,
    ),
    'R': AirspaceStyle( // Restricted
      fillColor: Color(0x40FF4500),
      borderColor: Color(0xFFFF4500),
      borderWidth: 2.0,
    ),
    'P': AirspaceStyle( // Prohibited
      fillColor: Color(0x508B0000),
      borderColor: Color(0xFF8B0000),
      borderWidth: 2.5,
    ),
    'A': AirspaceStyle( // Class A
      fillColor: Color(0x20800080),
      borderColor: Color(0xFF800080),
    ),
    'B': AirspaceStyle( // Class B
      fillColor: Color(0x200000FF),
      borderColor: Color(0xFF0000FF),
    ),
    'C': AirspaceStyle( // Class C
      fillColor: Color(0x20FF00FF),
      borderColor: Color(0xFFFF00FF),
    ),
    'E': AirspaceStyle( // Class E
      fillColor: Color(0x20008000),
      borderColor: Color(0xFF008000),
    ),
    'F': AirspaceStyle( // Class F
      fillColor: Color(0x20808080),
      borderColor: Color(0xFF808080),
    ),
    'G': AirspaceStyle( // Class G
      fillColor: Color(0x20C0C0C0),
      borderColor: Color(0xFFC0C0C0),
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
    final apiKey = await _openAipService.getApiKey();

    // Build API URL with optional API key as query parameter
    var url = '$_coreApiBase/airspaces'
        '?bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}'
        '&limit=$_defaultLimit';

    // Add API key as query parameter if available (common method)
    if (apiKey != null && apiKey.isNotEmpty) {
      url += '&apiKey=$apiKey';
    }

    LoggingService.structured('AIRSPACE_API_REQUEST', {
      'url': url,
      'bbox': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      'has_api_key': apiKey != null && apiKey.isNotEmpty,
    });

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

      LoggingService.structured('AIRSPACE_API_RESPONSE', {
        'status_code': response.statusCode,
        'content_length': response.body.length,
        'content_type': response.headers['content-type'],
      });

      if (response.statusCode == 200) {
        // Convert OpenAIP format to standard GeoJSON
        return _convertToGeoJson(response.body);
      } else {
        // For authentication errors or API failures, use sample data for demo purposes
        LoggingService.info('API failed with status ${response.statusCode}, using sample airspace data for demo');
        return _getSampleGeoJson(bounds);
      }

    } catch (error, stackTrace) {
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

    LoggingService.structured('AIRSPACE_SAMPLE_DATA', {
      'feature_count': (sampleGeoJson['features'] as List).length,
      'bounds': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      'note': 'Using demo airspace data for testing',
    });

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

    // Extract properties
    final properties = <String, dynamic>{
      'name': item['name'] ?? 'Unknown Airspace',
      'type': item['type'] ?? 'UNKNOWN',
      'class': item['class'],
      'upperLimit': item['upperLimit'],
      'lowerLimit': item['lowerLimit'],
      'country': item['country'],
    };

    return {
      'type': 'Feature',
      'geometry': geometry,
      'properties': properties,
    };
  }

  /// Parse GeoJSON string and return styled polygons for flutter_map
  Future<List<fm.Polygon>> parseAirspaceGeoJson(String geoJsonString, double opacity) async {
    try {
      // Use geobase to parse the GeoJSON data
      final featureCollection = geo.FeatureCollection.parse(geoJsonString);

      final polygons = <fm.Polygon>[];

      for (final feature in featureCollection.features) {
        final geometry = feature.geometry;
        final properties = feature.properties;

        if (geometry != null) {
          // Handle different geometry types
          if (geometry is geo.GeometryCollection) {
            // Handle geometry collections
            for (final geom in geometry.geometries) {
              final polygon = _createPolygonFromGeometry(geom, properties, opacity);
              if (polygon != null) polygons.add(polygon);
            }
          } else {
            final polygon = _createPolygonFromGeometry(geometry, properties, opacity);
            if (polygon != null) polygons.add(polygon);
          }
        }
      }

      LoggingService.structured('GEOJSON_PARSING', {
        'features_count': featureCollection.features.length,
        'polygons_created': polygons.length,
        'geojson_size': geoJsonString.length,
      });

      // Add airspace statistics logging
      _logAirspaceStatistics(featureCollection);

      return polygons;

    } catch (error, stackTrace) {
      LoggingService.error('Failed to parse airspace GeoJSON', error, stackTrace);
      rethrow;
    }
  }

  /// Create a flutter_map Polygon from a geobase geometry
  /// Log statistics about airspace types and distribution
  void _logAirspaceStatistics(geo.FeatureCollection featureCollection) {
    final Map<String, int> typeStats = {};
    final Map<String, int> originalTypeStats = {};
    double minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0;

    for (final feature in featureCollection.features) {
      final props = feature.properties;
      if (props != null && props.isNotEmpty) {
        // Count by mapped type
        final originalType = props['type']?.toString() ?? 'null';
        final mappedType = _mapOpenAipTypeToStyle(props['type']);

        typeStats[mappedType] = (typeStats[mappedType] ?? 0) + 1;
        originalTypeStats[originalType] = (originalTypeStats[originalType] ?? 0) + 1;

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

    LoggingService.structured('AIRSPACE_STATISTICS', {
      'mapped_types': typeStats,
      'original_types': originalTypeStats,
      'coverage_bounds': {
        'min_lat': minLat.toStringAsFixed(3),
        'max_lat': maxLat.toStringAsFixed(3),
        'min_lon': minLon.toStringAsFixed(3),
        'max_lon': maxLon.toStringAsFixed(3),
        'area_degrees': ((maxLat - minLat) * (maxLon - minLon)).toStringAsFixed(2),
      },
    });
  }

  fm.Polygon? _createPolygonFromGeometry(geo.Geometry geometry, Map<String, dynamic>? properties, double opacity) {
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

      // Get airspace style based on type (handle both String and int from OpenAIP)
      final typeValue = props['type'];
      final mappedType = _mapOpenAipTypeToStyle(typeValue);
      final style = _airspaceStyles[mappedType] ?? _getDefaultStyle();

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

      return fm.Polygon(
        points: points,
        color: style.fillColor.withValues(alpha: opacity),
        borderColor: style.borderColor,
        borderStrokeWidth: style.borderWidth,
        // Note: Store airspace data for future interactive features
        // For now, we'll handle interactions at the layer level
      );

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

  /// Get style for airspace type (for legend/UI purposes)
  AirspaceStyle getStyleForType(String type) {
    return _airspaceStyles[type.toUpperCase()] ?? _getDefaultStyle();
  }

  /// Get all defined airspace types with their styles
  Map<String, AirspaceStyle> get allAirspaceStyles => Map.from(_airspaceStyles);
}