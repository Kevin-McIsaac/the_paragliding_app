import 'dart:async';
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

  /// Enable or disable country mode
  Future<void> setCountryMode(bool enabled) async {
    _useCountryMode = enabled;
    if (enabled) {
      LoggingService.info('Switched to country-based airspace caching mode');
    } else {
      LoggingService.info('Switched to tile-based airspace caching mode');
    }
  }

  /// Check if any countries are loaded
  Future<bool> hasLoadedCountries() async {
    final countries = await AirspaceDiskCache.instance.getCachedCountries();
    return countries.isNotEmpty;
  }

  /// Fetch airspace data - uses country mode if countries are loaded, otherwise tile mode
  Future<String> fetchAirspaceGeoJson(fm.LatLngBounds bounds) async {
    // Check if we should use country mode
    final hasCountries = await hasLoadedCountries();
    if (hasCountries) {
      _useCountryMode = true;
      return _fetchAirspaceFromCountries(bounds);
    } else {
      _useCountryMode = false;
      return _fetchAirspaceFromTiles(bounds);
    }
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

    // Convert to GeoJSON
    final conversionStopwatch = Stopwatch()..start();
    final features = geometries.map((geometry) => _geometryToFeature(geometry)).toList();
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
  Future<String> _fetchAirspaceFromTiles(fm.LatLngBounds bounds) async {
    final overallStopwatch = Stopwatch()..start();
    final memoryBefore = PerformanceMonitor.getMemoryUsageMB();

    // Timing breakdowns for viewport processing
    final tileCalcStopwatch = Stopwatch()..start();

    // Calculate tiles for the viewport
    final tileKeys = _calculateTileKeys(bounds);
    tileCalcStopwatch.stop();

    // Check which tiles need fetching
    final cacheLookupStopwatch = Stopwatch()..start();
    final tilesToFetch = await _metadataCache.getTilesToFetch(tileKeys);
    cacheLookupStopwatch.stop();

    var tilesFromCache = tileKeys.length - tilesToFetch.length;
    var tilesFromApi = 0;
    var emptyTiles = 0;

    // Fetch missing tiles from API
    if (tilesToFetch.isNotEmpty) {
      final apiKey = await _openAipService.getApiKey();

      // EXPERIMENTAL: Batch API call optimization
      // Make a single API call for the entire area covered by all tiles
      // Then map features back to their respective tiles

      LoggingService.structured('BATCH_API_EXPERIMENT', {
        'tiles_to_fetch': tilesToFetch.length,
        'tile_keys': tilesToFetch,
      });

      // Calculate the combined bounding box for all tiles
      final combinedBounds = _calculateCombinedBounds(tilesToFetch);

      LoggingService.structured('BATCH_BOUNDS_CALCULATED', {
        'individual_tiles': tilesToFetch.length,
        'combined_bounds': '${combinedBounds.west},${combinedBounds.south},${combinedBounds.east},${combinedBounds.north}',
      });

      // Make a single API call for the entire combined area
      final batchStopwatch = Stopwatch()..start();

      try {
        // Fetch all features for the combined area
        final allFeatures = await _fetchAllPagesForTile(combinedBounds, apiKey, 'batch_${tilesToFetch.length}');
        batchStopwatch.stop();

        LoggingService.structured('BATCH_API_COMPLETE', {
          'duration_ms': batchStopwatch.elapsedMilliseconds,
          'features_retrieved': allFeatures.length,
          'tiles_covered': tilesToFetch.length,
          'ms_per_tile': tilesToFetch.isNotEmpty ? (batchStopwatch.elapsedMilliseconds / tilesToFetch.length).round() : 0,
        });

        // Map features back to their respective tiles
        final Map<String, List<Map<String, dynamic>>> tileFeatures = {};

        // Initialize empty lists for each tile
        for (final tileKey in tilesToFetch) {
          tileFeatures[tileKey] = [];
        }

        // Distribute features to their respective tiles based on location
        for (final feature in allFeatures) {
          // Determine which tile(s) this feature belongs to
          final featureTiles = _determineFeatureTiles(feature, tilesToFetch);

          // Add feature to each relevant tile
          for (final tileKey in featureTiles) {
            if (tileFeatures.containsKey(tileKey)) {
              tileFeatures[tileKey]!.add(feature);
            }
          }
        }

        // Count tiles and log distribution
        for (final entry in tileFeatures.entries) {
          if (entry.value.isEmpty) {
            emptyTiles++;
          } else {
            tilesFromApi++;
          }
        }

        LoggingService.structured('BATCH_DISTRIBUTION_COMPLETE', {
          'total_features': allFeatures.length,
          'tiles_with_data': tilesFromApi,
          'empty_tiles': emptyTiles,
          'distribution': tileFeatures.map((k, v) => MapEntry(k, v.length)),
        });

        // Clear pending fetch markers
        for (final tileKey in tilesToFetch) {
          _metadataCache.clearPendingFetch(tileKey);
        }

        // Batch process all tiles together to avoid redundant geometry retrievals
        if (tileFeatures.isNotEmpty) {
          await _metadataCache.putMultipleTilesMetadata(tileFeatures);
        }

        // Log API request performance
        _performanceLogger.logApiRequest(
          endpoint: 'airspaces_batch',
          duration: batchStopwatch.elapsed,
          resultCount: allFeatures.length,
          bounds: '${combinedBounds.west},${combinedBounds.south},${combinedBounds.east},${combinedBounds.north}',
        );

      } catch (error, stackTrace) {
        LoggingService.error('Failed to fetch batch tiles', error, stackTrace);

        // Clear all pending fetch markers on error
        for (final tileKey in tilesToFetch) {
          _metadataCache.clearPendingFetch(tileKey);
        }
      }
    }

    // Get all airspaces for the requested tiles
    final geometryFetchStopwatch = Stopwatch()..start();
    final geometries = await _metadataCache.getAirspacesForTiles(tileKeys);
    geometryFetchStopwatch.stop();

    // Summary logged in VIEWPORT_PROCESSING instead

    // Convert to GeoJSON
    final conversionStopwatch = Stopwatch()..start();
    final features = geometries.map((geometry) => _geometryToFeature(geometry)).toList();
    conversionStopwatch.stop();

    final geoJson = {
      'type': 'FeatureCollection',
      'features': features,
    };

    final mergedGeoJson = json.encode(geoJson);

    overallStopwatch.stop();
    final memoryAfter = PerformanceMonitor.getMemoryUsageMB();

    // Log detailed viewport processing breakdown
    LoggingService.structured('VIEWPORT_BREAKDOWN', {
      'tile_calc_ms': tileCalcStopwatch.elapsedMilliseconds,
      'cache_lookup_ms': cacheLookupStopwatch.elapsedMilliseconds,
      'geometry_fetch_ms': geometryFetchStopwatch.elapsedMilliseconds,
      'conversion_ms': conversionStopwatch.elapsedMilliseconds,
      'api_fetch_ms': tilesToFetch.isEmpty ? 0 : (overallStopwatch.elapsedMilliseconds -
          tileCalcStopwatch.elapsedMilliseconds -
          cacheLookupStopwatch.elapsedMilliseconds -
          geometryFetchStopwatch.elapsedMilliseconds -
          conversionStopwatch.elapsedMilliseconds),
      'total_ms': overallStopwatch.elapsedMilliseconds,
      'tiles_requested': tileKeys.length,
      'tiles_fetched': tilesToFetch.length,
      'unique_airspaces': features.length,
    });

    // Log memory usage
    LoggingService.structured('MEMORY_USAGE', {
      'operation': 'airspace_viewport_load',
      'before_mb': memoryBefore.toStringAsFixed(1),
      'after_mb': memoryAfter.toStringAsFixed(1),
      'delta_mb': (memoryAfter - memoryBefore).toStringAsFixed(1),
      'airspaces_loaded': features.length,
    });

    // Log viewport processing metrics
    _performanceLogger.logViewportProcessing(
      tilesRequested: tileKeys.length,
      tilesCached: tilesFromCache,
      tilesEmpty: emptyTiles,
      uniqueAirspaces: features.length,
      totalDuration: overallStopwatch.elapsed,
    );

    // Log overall performance
    LoggingService.performance(
      'Airspace Fetch (Hierarchical)',
      overallStopwatch.elapsed,
      'tiles=${tileKeys.length}, cached=$tilesFromCache, fetched=$tilesFromApi, airspaces=${features.length}',
    );

    return mergedGeoJson;
  }

  /// Calculate tile keys for the viewport
  List<String> _calculateTileKeys(fm.LatLngBounds bounds) {
    final zoom = 8; // Fixed zoom level for now, could be dynamic
    final tiles = <String>[];

    // Calculate tile bounds
    final minX = _lonToTileX(bounds.west, zoom);
    final maxX = _lonToTileX(bounds.east, zoom);
    final minY = _latToTileY(bounds.north, zoom);
    final maxY = _latToTileY(bounds.south, zoom);

    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        tiles.add(_metadataCache.generateTileKey(zoom, x, y));
      }
    }

    return tiles;
  }

  /// Convert longitude to tile X coordinate
  int _lonToTileX(double lon, int zoom) {
    return ((lon + 180.0) / 360.0 * math.pow(2, zoom)).floor();
  }

  /// Convert latitude to tile Y coordinate
  int _latToTileY(double lat, int zoom) {
    final latRad = lat * (math.pi / 180.0);
    return ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * math.pow(2, zoom)).floor();
  }

  /// Helper function for hyperbolic sine (not available in dart:math)
  double _sinh(double x) {
    return (math.exp(x) - math.exp(-x)) / 2;
  }

  /// Get tile bounds from tile key
  fm.LatLngBounds _getTileBounds(String tileKey) {
    final components = _metadataCache.parseTileKey(tileKey);
    if (components == null) {
      return fm.LatLngBounds(LatLng(-90, -180), LatLng(90, 180));
    }

    final zoom = components['zoom']!;
    final x = components['x']!;
    final y = components['y']!;

    final n = math.pow(2, zoom);
    final west = x / n * 360.0 - 180.0;
    final east = (x + 1) / n * 360.0 - 180.0;
    final north = math.atan(_sinh(math.pi * (1 - 2 * y / n))) * 180.0 / math.pi;
    final south = math.atan(_sinh(math.pi * (1 - 2 * (y + 1) / n))) * 180.0 / math.pi;

    return fm.LatLngBounds(LatLng(south, west), LatLng(north, east));
  }

  /// Calculate combined bounding box for multiple tiles
  fm.LatLngBounds _calculateCombinedBounds(List<String> tileKeys) {
    if (tileKeys.isEmpty) {
      return fm.LatLngBounds(LatLng(-90, -180), LatLng(90, 180));
    }

    double minLat = 90.0;
    double maxLat = -90.0;
    double minLng = 180.0;
    double maxLng = -180.0;

    for (final tileKey in tileKeys) {
      final tileBounds = _getTileBounds(tileKey);
      minLat = math.min(minLat, tileBounds.south);
      maxLat = math.max(maxLat, tileBounds.north);
      minLng = math.min(minLng, tileBounds.west);
      maxLng = math.max(maxLng, tileBounds.east);
    }

    return fm.LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  /// Determine which tiles a feature belongs to based on its geometry
  List<String> _determineFeatureTiles(Map<String, dynamic> feature, List<String> tileKeys) {
    final geometry = feature['geometry'];
    if (geometry == null || geometry is! Map) {
      return [];
    }

    final type = geometry['type'] as String?;
    final coordinates = geometry['coordinates'];
    if (type == null || coordinates == null) {
      return [];
    }

    // Extract bounds of the feature
    double minLat = 90.0, maxLat = -90.0, minLng = 180.0, maxLng = -180.0;

    if (type == 'Polygon' && coordinates is List) {
      // Process single polygon
      for (final ring in coordinates) {
        if (ring is List) {
          for (final point in ring) {
            if (point is List && point.length >= 2) {
              final lng = point[0] as num;
              final lat = point[1] as num;
              minLat = math.min(minLat, lat.toDouble());
              maxLat = math.max(maxLat, lat.toDouble());
              minLng = math.min(minLng, lng.toDouble());
              maxLng = math.max(maxLng, lng.toDouble());
            }
          }
        }
      }
    } else if (type == 'MultiPolygon' && coordinates is List) {
      // Process multiple polygons
      for (final polygon in coordinates) {
        if (polygon is List) {
          for (final ring in polygon) {
            if (ring is List) {
              for (final point in ring) {
                if (point is List && point.length >= 2) {
                  final lng = point[0] as num;
                  final lat = point[1] as num;
                  minLat = math.min(minLat, lat.toDouble());
                  maxLat = math.max(maxLat, lat.toDouble());
                  minLng = math.min(minLng, lng.toDouble());
                  maxLng = math.max(maxLng, lng.toDouble());
                }
              }
            }
          }
        }
      }
    }

    // Check which tiles this feature overlaps with
    final overlappingTiles = <String>[];
    final featureBounds = fm.LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));

    for (final tileKey in tileKeys) {
      final tileBounds = _getTileBounds(tileKey);

      // Check if feature bounds overlaps with tile bounds
      if (!(featureBounds.south > tileBounds.north ||
            featureBounds.north < tileBounds.south ||
            featureBounds.west > tileBounds.east ||
            featureBounds.east < tileBounds.west)) {
        overlappingTiles.add(tileKey);
      }
    }

    return overlappingTiles;
  }

  /// Extract features from API response
  List<Map<String, dynamic>> _extractFeatures(dynamic data) {
    List<dynamic> items;
    if (data is Map) {
      // OpenAIP returns GeoJSON FeatureCollection with 'features' array
      items = data['features'] ?? data['items'] ?? [];
    } else if (data is List) {
      items = data;
    } else {
      LoggingService.warning('Unexpected API response type: ${data.runtimeType}');
      return [];
    }

    // Properly cast each feature to Map<String, dynamic>
    final features = <Map<String, dynamic>>[];
    for (final item in items) {
      if (item is Map) {
        // Deep cast the map to ensure all nested maps are properly typed
        final feature = _deepCastMap(item);
        features.add(feature);
      }
    }

    return features;
  }

  /// Deep cast a dynamic map to Map<String, dynamic>
  Map<String, dynamic> _deepCastMap(Map map) {
    final result = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;

      if (value is Map) {
        result[key] = _deepCastMap(value);
      } else if (value is List) {
        result[key] = value.map((item) {
          if (item is Map) {
            return _deepCastMap(item);
          }
          return item;
        }).toList();
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  /// Convert cached geometry to GeoJSON feature
  Map<String, dynamic> _geometryToFeature(CachedAirspaceGeometry geometry) {
    // Convert polygons to GeoJSON coordinates
    final coordinates = geometry.polygons.map((polygon) {
      return polygon.map((point) => [point.longitude, point.latitude]).toList();
    }).toList();

    // Ensure the type field contains the numeric type code
    final properties = Map<String, dynamic>.from(geometry.properties);
    properties['type'] = geometry.typeCode; // Use the stored numeric type code

    // Ensure ICAO class is available for AirspaceData creation
    // The 'class' field should already be in properties from when we stored it,
    // but ensure it's present for compatibility
    if (!properties.containsKey('class') && properties.containsKey('icaoClass')) {
      properties['class'] = properties['icaoClass'];
    }

    return {
      'type': 'Feature',
      'geometry': {
        'type': geometry.polygons.length == 1 ? 'Polygon' : 'MultiPolygon',
        'coordinates': geometry.polygons.length == 1 ? coordinates : [coordinates],
      },
      'properties': properties,
    };
  }

  /// Fetch all pages for a single tile using pagination
  Future<List<Map<String, dynamic>>> _fetchAllPagesForTile(
    fm.LatLngBounds tileBounds,
    String? apiKey,
    String tileKey,
  ) async {
    final allFeatures = <Map<String, dynamic>>[];
    int page = 1;
    int totalPages = 0;
    int totalApiCalls = 0;
    final paginationStopwatch = Stopwatch()..start();

    // Pagination tracking without verbose logging

    do {
      // Build API URL with pagination
      var url = '$_coreApiBase/airspaces'
          '?bbox=${tileBounds.west},${tileBounds.south},${tileBounds.east},${tileBounds.north}'
          '&limit=$_defaultLimit&page=$page';

      if (apiKey != null && apiKey.isNotEmpty) {
        url += '&apiKey=$apiKey';
      }

      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'FreeFlightLog/1.0',
      };

      // API request logging reduced to errors only

      final pageStopwatch = Stopwatch()..start();
      final response = await _makeRequestWithRetry(url, headers, page, tileKey);
      pageStopwatch.stop();
      totalApiCalls++;

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = _extractFeatures(data);

        // Log page details
        // Success tracked silently unless there's an issue

        allFeatures.addAll(features);

        // If we got fewer features than the limit, we've reached the last page
        if (features.length < _defaultLimit) {
          totalPages = page;
          break;
        }

        page++;
      } else {
        LoggingService.error('API request failed',
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          StackTrace.current);
        break;
      }

      // Safety check: prevent infinite loops in case of API issues
      if (page > 10) { // Reasonable limit: 10 pages × 1000 = 10,000 airspaces per tile
        LoggingService.warning('Pagination safety limit reached for tile $tileKey (10 pages)');
        totalPages = page - 1;
        break;
      }
    } while (true);

    paginationStopwatch.stop();

    // Log only if pagination took multiple pages or was slow
    if (totalPages > 1 || paginationStopwatch.elapsedMilliseconds > 1000) {
      LoggingService.debug('Pagination complete: $totalPages pages, ${allFeatures.length} features in ${paginationStopwatch.elapsedMilliseconds}ms');
    }

    // Log a warning if we found a lot of airspaces (indicates high density area)
    if (allFeatures.length > 2000) {
      LoggingService.warning('High airspace density detected in tile $tileKey: ${allFeatures.length} airspaces');
    }

    return allFeatures;
  }

  /// Make HTTP request with retry logic and exponential backoff
  Future<http.Response> _makeRequestWithRetry(
    String url,
    Map<String, String> headers,
    int page,
    String tileKey,
  ) async {
    const maxRetries = 3;
    const baseDelayMs = 1000; // Start with 1 second

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Only log on first attempt or final retry
        if (attempt == 1 || attempt == maxRetries) {
          LoggingService.debug('API request attempt $attempt/$maxRetries for tile $tileKey');
        }

        final response = await http.get(
          Uri.parse(url),
          headers: headers,
        ).timeout(_requestTimeout);

        // Success case
        if (response.statusCode == 200) {
          if (attempt > 1) {
            LoggingService.debug('API request succeeded after $attempt attempts for tile $tileKey');
          }
          return response;
        }

        // Handle rate limiting (429)
        if (response.statusCode == 429) {
          final retryAfter = response.headers['retry-after'];
          final waitTime = retryAfter != null ? int.tryParse(retryAfter) ?? 5 : 5;

          LoggingService.structured('API_RATE_LIMITED', {
            'status_code': response.statusCode,
            'retry_after_seconds': waitTime,
            'attempt': attempt,
            'page': page,
            'tile_key': tileKey,
          });

          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: waitTime));
            continue;
          }
        }

        // Other HTTP errors
        if (attempt < maxRetries) {
          final delayMs = baseDelayMs * (1 << (attempt - 1)); // Exponential backoff: 1s, 2s, 4s

          // Only log if this is becoming a pattern
          if (attempt == 2) {
            LoggingService.debug('API request failed with ${response.statusCode}, retrying...');
          }

          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        // Final attempt failed
        LoggingService.warning('API request failed after $attempt attempts: ${response.statusCode} for tile $tileKey');

        return response;

      } on TimeoutException catch (e) {
        if (attempt < maxRetries) {
          final delayMs = baseDelayMs * (1 << (attempt - 1)); // Exponential backoff

          if (attempt == 2) {
            LoggingService.debug('API request timeout, retrying...');
          }

          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        // Final timeout
        LoggingService.error('API request timeout after $maxRetries attempts', e, StackTrace.current);
        rethrow;

      } catch (e) {
        if (attempt < maxRetries) {
          final delayMs = baseDelayMs * (1 << (attempt - 1)); // Exponential backoff

          if (attempt == 2) {
            LoggingService.debug('API request error: ${e.toString().split('\n').first}, retrying...');
          }

          await Future.delayed(Duration(milliseconds: delayMs));
          continue;
        }

        // Final error
        LoggingService.error('API request failed after $maxRetries attempts', e, StackTrace.current);
        rethrow;
      }
    }

    // This shouldn't be reached, but just in case
    throw Exception('Request failed after $maxRetries attempts');
  }

  /// Legacy method for direct API fetch without caching (kept for fallback)
  Future<String> _fetchDirectFromApi(fm.LatLngBounds bounds) async {
    final stopwatch = Stopwatch()..start();
    final apiKey = await _openAipService.getApiKey();

    var url = '$_coreApiBase/airspaces'
        '?bbox=${bounds.west},${bounds.south},${bounds.east},${bounds.north}'
        '&limit=$_defaultLimit';

    if (apiKey != null && apiKey.isNotEmpty) {
      url += '&apiKey=$apiKey';
    }

    try {
      final headers = <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'FreeFlightLog/1.0',
      };

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(_requestTimeout);

      stopwatch.stop();

      if (response.statusCode == 200) {
        LoggingService.performance(
          'Direct API Fetch',
          Duration(milliseconds: stopwatch.elapsedMilliseconds),
          'status=200'
        );
        return _convertToGeoJson(response.body);
      } else {
        LoggingService.info('API failed with status ${response.statusCode}, using sample airspace data');
        return _getSampleGeoJson(bounds);
      }
    } catch (error, stackTrace) {
      LoggingService.error('Failed to fetch airspace data', error, stackTrace);
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
          // Apply polygon clipping to remove overlapping areas
          // Note: viewport filtering already done above, so no need to filter again in clipping
          final clippingStopwatch = Stopwatch()..start();
          final clippedPolygons = _applyPolygonClipping(polygonsWithAltitude, viewport);
          clippingStopwatch.stop();

          // Convert clipped polygons back to flutter_map format
          polygons = _convertClippedPolygonsToFlutterMap(clippedPolygons, opacity);

          // For clipped polygons, keep original boundaries for tooltip hit testing
          identificationPolygons = polygonsWithAltitude.map((p) => p.data).toList();

          // Performance log for clipping
          LoggingService.structured('CLIPPING_PERFORMANCE', {
            'polygons_input': polygonsWithAltitude.length,
            'polygons_output': polygons.length,
            'clipping_time_ms': clippingStopwatch.elapsedMilliseconds,
          });

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

  /// Subtract multiple polygons from a subject polygon using boolean difference
  /// Returns list of resulting polygons (may be empty, single, or multiple)
  List<_ClippedPolygonData> _subtractPolygonsFromSubject({
    required List<LatLng> subjectPoints,
    required List<List<LatLng>> clippingPolygons,
    required List<AirspaceData> clippingAirspaceData,
    required AirspaceData airspaceData,
    required AirspaceStyle style,
  }) {
    final stopwatch = Stopwatch()..start();
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

      // Track completely clipped airspaces (don't log individually, will summarize later)
      if (results.isEmpty && subjectPoints.isNotEmpty) {
        // This will be tracked and summarized in the main clipping method
      }

      stopwatch.stop();

      // Only log slow clipping operations
      if (stopwatch.elapsedMilliseconds > 10) {
        LoggingService.structured('POLYGON_CLIPPING_OPERATION', {
          'subject_points': subjectPoints.length,
          'clipping_polygons': clippingPolygons.length,
          'clipping_total_points': clippingPolygons.fold<int>(0, (sum, p) => sum + p.length),
          'result_polygons': results.length,
          'airspace_name': airspaceData.name,
          'time_ms': stopwatch.elapsedMilliseconds,
        });
      }

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

    // Track timing for clipping operations
    int totalClippingTimeMs = 0;
    int longestClippingTimeMs = 0;
    String? longestClippingAirspace;
    final Map<String, int> clippingTimeByType = {};

    final clippingMemoryBefore = PerformanceMonitor.getMemoryUsageMB();

    LoggingService.structured('AIRSPACE_CLIPPING_START', {
      'input_polygons': polygonsWithAltitude.length,
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

    LoggingService.structured('CLIPPING_STAGE', {
      'input_polygons': polygonsWithAltitude.length,
      'polygons_to_clip': visibleAirspaces.length,
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

      // Perform clipping operation with timing
      final clippingStopwatch = Stopwatch()..start();
      final clippedResults = _subtractPolygonsFromSubject(
        subjectPoints: currentPoints,
        clippingPolygons: clippingPolygons,
        clippingAirspaceData: clippingAirspaceData,
        airspaceData: airspaceData,
        style: style,
      );
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

    // Log detailed clipping performance
    LoggingService.structured('CLIPPING_DETAILED_PERFORMANCE', {
      'total_clipping_time_ms': totalClippingTimeMs,
      'average_time_ms': visibleAirspaces.isNotEmpty ? (totalClippingTimeMs / visibleAirspaces.length).round() : 0,
      'longest_time_ms': longestClippingTimeMs,
      'longest_airspace': longestClippingAirspace,
      'completely_clipped': completelyClippedCount,
      'time_by_type': clippingTimeByType,
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

  /// Dispose resources
  void dispose() {
    _performanceLogger.dispose();
  }
}