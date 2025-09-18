import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:latlong2/latlong.dart';
import '../services/openaip_service.dart';
import '../services/airspace_geojson_service.dart';
import '../services/logging_service.dart';
import '../data/models/airspace_enums.dart';

/// Manages all OpenAIP aviation data overlay layers for flutter_map
class AirspaceOverlayManager {
  static AirspaceOverlayManager? _instance;
  static AirspaceOverlayManager get instance => _instance ??= AirspaceOverlayManager._();

  AirspaceOverlayManager._();

  final OpenAipService _openAipService = OpenAipService.instance;
  final AirspaceGeoJsonService _geoJsonService = AirspaceGeoJsonService.instance;

  // Cache for bounds tracking
  String _lastBoundsKey = '';

  // Debouncing for map movement
  Timer? _debounceTimer;
  String? _currentRequestId;
  int _requestCounter = 0;
  int _debouncedRequestsCount = 0;
  int _cancelledRequestsCount = 0;

  /// Build all overlay layers for enabled OpenAIP data types
  Future<List<Widget>> buildEnabledOverlayLayers({
    required LatLng center,
    required double zoom,
    fm.LatLngBounds? visibleBounds,  // Accept actual viewport bounds
    double maxAltitudeFt = 30000.0,
  }) async {
    // Generate unique request ID for this request
    final requestId = 'req_${++_requestCounter}_${DateTime.now().millisecondsSinceEpoch}';
    _currentRequestId = requestId;

    // Use actual viewport bounds if provided, otherwise calculate from center/zoom
    final bounds = visibleBounds ?? _geoJsonService.calculateBoundingBox(center, zoom);
    final boundsKey = '${bounds.south},${bounds.west},${bounds.north},${bounds.east}';

    // Check if bounds overlap with cached data to avoid unnecessary work
    final shouldDebounce = _shouldDebounceRequest(bounds, boundsKey);

    LoggingService.structured('AVIATION_OVERLAY_BUILD', {
      'request_id': requestId,
      'center': '${center.latitude},${center.longitude}',
      'zoom': zoom,
      'bounds_key': boundsKey,
      'should_debounce': shouldDebounce,
    });

    // Cancel existing timer
    _debounceTimer?.cancel();

    if (shouldDebounce) {
      _debouncedRequestsCount++;

      // Use a Completer to handle the debounced response
      final completer = Completer<List<Widget>>();

      _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
        // Check if this request is still current
        if (_currentRequestId != requestId) {
          _cancelledRequestsCount++;
          LoggingService.structured('DEBOUNCE_REQUEST_CANCELLED', {
            'cancelled_request_id': requestId,
            'current_request_id': _currentRequestId,
            'total_cancelled_requests': _cancelledRequestsCount,
          });
          completer.complete(<Widget>[]);
          return;
        }

        try {
          LoggingService.structured('DEBOUNCE_REQUEST_EXECUTED', {
            'request_id': requestId,
            'total_debounced_requests': _debouncedRequestsCount,
            'delay_ms': 300,
          });
          final result = await _buildLayersInternal(center, zoom, bounds, boundsKey, requestId, maxAltitudeFt);
          completer.complete(result);
        } catch (error) {
          completer.completeError(error);
        }
      });

      return completer.future;
    } else {
      // No debouncing needed, execute immediately
      LoggingService.structured('IMMEDIATE_REQUEST_EXECUTED', {
        'request_id': requestId,
        'reason': 'no_debounce_needed',
      });
      return _buildLayersInternal(center, zoom, bounds, boundsKey, requestId, maxAltitudeFt);
    }
  }

  /// Internal method to build layers (called after debouncing logic)
  Future<List<Widget>> _buildLayersInternal(
    LatLng center,
    double zoom,
    fm.LatLngBounds bounds,
    String boundsKey,
    String requestId,
    double maxAltitudeFt,
  ) async {
    // Check if request is still current before proceeding
    if (_currentRequestId != requestId) {
      LoggingService.structured('REQUEST_CANCELLED_DURING_BUILD', {
        'cancelled_request_id': requestId,
        'current_request_id': _currentRequestId,
      });
      return <Widget>[];
    }

    final List<Widget> layers = [];

    // Build airspace polygons (bottom layer)
    if (await _openAipService.getAirspaceEnabled()) {
      try {
        final opacity = await _openAipService.getOverlayOpacity();
        final polygons = await _buildAirspacePolygons(bounds, opacity, maxAltitudeFt);

        if (polygons.isNotEmpty) {
          final polygonLayer = fm.PolygonLayer(
            polygons: polygons,
            polygonCulling: true,
          );
          layers.add(polygonLayer);
        }
      } catch (error, stackTrace) {
        LoggingService.error('Failed to build airspace layer', error, stackTrace);
      }
    }

    // Update bounds tracking
    _lastBoundsKey = boundsKey;

    return layers;
  }

  /// Check if request should be debounced based on bounds overlap
  bool _shouldDebounceRequest(fm.LatLngBounds bounds, String boundsKey) {
    // If this is the first request or bounds are completely different, don't debounce
    if (_lastBoundsKey.isEmpty) {
      return false;
    }

    // If bounds are exactly the same, don't debounce (likely a forced refresh)
    if (_lastBoundsKey == boundsKey) {
      return false;
    }

    // Parse previous bounds
    final lastParts = _lastBoundsKey.split(',');
    if (lastParts.length != 4) {
      return false; // Invalid previous bounds, don't debounce
    }

    try {
      final lastBounds = fm.LatLngBounds(
        LatLng(double.parse(lastParts[0]), double.parse(lastParts[1])), // SW
        LatLng(double.parse(lastParts[2]), double.parse(lastParts[3])), // NE
      );

      // Calculate overlap percentage
      final overlapPercent = _calculateBoundsOverlap(lastBounds, bounds);

      // Debounce if there's significant overlap (>50% suggests small movement)
      return overlapPercent > 0.5;
    } catch (e) {
      LoggingService.error('Error parsing previous bounds for debounce check', e);
      return false;
    }
  }

  /// Calculate overlap percentage between two bounds
  double _calculateBoundsOverlap(fm.LatLngBounds bounds1, fm.LatLngBounds bounds2) {
    // Calculate intersection bounds
    final intersectionSouth = math.max(bounds1.south, bounds2.south);
    final intersectionNorth = math.min(bounds1.north, bounds2.north);
    final intersectionWest = math.max(bounds1.west, bounds2.west);
    final intersectionEast = math.min(bounds1.east, bounds2.east);

    // Check if there's any intersection
    if (intersectionSouth >= intersectionNorth || intersectionWest >= intersectionEast) {
      return 0.0; // No overlap
    }

    // Calculate areas
    final intersectionArea = (intersectionNorth - intersectionSouth) * (intersectionEast - intersectionWest);
    final bounds1Area = (bounds1.north - bounds1.south) * (bounds1.east - bounds1.west);
    final bounds2Area = (bounds2.north - bounds2.south) * (bounds2.east - bounds2.west);

    // Return overlap as percentage of the smaller bounds
    final smallerArea = math.min(bounds1Area, bounds2Area);
    return smallerArea > 0 ? intersectionArea / smallerArea : 0.0;
  }

  /// Build airspace polygons from GeoJSON data
  Future<List<fm.Polygon>> _buildAirspacePolygons(fm.LatLngBounds bounds, double opacity, double maxAltitudeFt) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Use the bounds passed from buildEnabledOverlayLayers

      LoggingService.structured('AIRSPACE_FETCH_START', {
        'bounds': '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
      });

      // Get excluded airspace types and ICAO classes for filtering (now enum-based)
      final excludedTypesMap = await _openAipService.getExcludedAirspaceTypes();
      final excludedClassesMap = await _openAipService.getExcludedIcaoClasses();

      // Convert Maps to Sets of excluded items
      final excludedTypes = excludedTypesMap.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key)
          .toSet();

      final excludedClasses = excludedClassesMap.entries
          .where((entry) => entry.value)
          .map((entry) => entry.key.abbreviation)  // Convert IcaoClass enum to string abbreviation (A, B, C, etc.)
          .toSet();

      // Get clipping preference
      final clippingEnabled = await _openAipService.isClippingEnabled();

      // Time the airspace processing/clipping step
      final processingStopwatch = Stopwatch()..start();

      // Fetch and process airspace polygons directly (optimized path - no GeoJSON conversion)
      final polygons = await _geoJsonService.fetchAirspacePolygonsDirect(
        bounds,
        opacity,
        excludedTypes,
        excludedClasses,
        maxAltitudeFt,
        clippingEnabled,
      );

      processingStopwatch.stop();
      stopwatch.stop();

      // Performance warning if processing is slow
      final totalTime = stopwatch.elapsedMilliseconds;
      final processingTime = processingStopwatch.elapsedMilliseconds;

      if (totalTime > 1000) {
        LoggingService.info('[PERF WARNING] Airspace processing took ${totalTime}ms (threshold: 1000ms)');
      } else if (processingTime > 500) {
        LoggingService.info('[PERF WARNING] Airspace parsing took ${processingTime}ms (threshold: 500ms)');
      }

      // Simple success log
      LoggingService.info('[AIRSPACE] Loaded ${polygons.length} airspaces in ${totalTime}ms');

      return polygons;

    } catch (error, stackTrace) {
      stopwatch.stop();

      LoggingService.performance(
        'Airspace Processing (Error)',
        Duration(milliseconds: stopwatch.elapsedMilliseconds),
        'error=true'
      );

      LoggingService.error('Failed to build airspace polygons', error, stackTrace);
      // Return empty list to continue without airspace data
      return [];
    }
  }
  



  /// Check if any overlay layers are enabled
  Future<bool> hasEnabledLayers() async {
    return await _openAipService.getAirspaceEnabled();
  }

  /// Get count of enabled layers
  Future<int> getEnabledLayerCount() async {
    int count = 0;
    if (await _openAipService.getAirspaceEnabled()) count++;
    return count;
  }
  
  /// Build a comprehensive legend widget for all enabled aviation layers
  Future<Widget?> buildLayerLegend(BuildContext context) async {
    final hasEnabledData = await hasEnabledLayers();

    if (!hasEnabledData) {
      return null;
    }

    final List<Widget> legendItems = [];

    // Add airspace legend if enabled
    if (await _openAipService.getAirspaceEnabled()) {
      final visibleAirspaceTypes = _geoJsonService.visibleAirspaceTypes;

      if (visibleAirspaceTypes.isNotEmpty) {
        // Map numeric type codes to string type names
        final Set<String> visibleTypeNames = {};
        for (final typeCode in visibleAirspaceTypes) {
          // Map the numeric code to the string type name
          final typeName = _mapNumericTypeToString(typeCode.code);
          if (typeName != null) {
            visibleTypeNames.add(typeName);
          }
        }

        final airspaceLegendItems = await Future.value(
          // Use the existing airspace legend from SiteMarkerUtils
          _geoJsonService.allAirspaceStyles.entries
              .where((entry) => visibleTypeNames.contains(entry.key))
              .map((entry) => _buildAirspaceLegendItem(entry.key, entry.value))
              .toList(),
        );

        if (airspaceLegendItems.isNotEmpty) {
          legendItems.addAll(airspaceLegendItems);
          legendItems.add(const SizedBox(height: 4));
        }
      }
    }

    // No aviation data legends anymore

    if (legendItems.isEmpty) {
      return null;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Aviation Data',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ...legendItems,
          const SizedBox(height: 2),
          Text(
            'Source: OpenAIP',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  /// Build a single legend item for an airspace type
  Widget _buildAirspaceLegendItem(String type, AirspaceStyle style) {
    final typeNames = {
      'CTR': 'Control Zone',
      'TMA': 'Terminal Area',
      'CTA': 'Control Area',
      'D': 'Danger',
      'R': 'Restricted',
      'P': 'Prohibited',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 6,
            decoration: BoxDecoration(
              color: style.fillColor,
              border: Border.all(
                color: style.borderColor,
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$type - ${typeNames[type] ?? type}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Validate that required dependencies are available
  static bool validateDependencies() {
    try {
      // Check if flutter_map and GeoJSON dependencies are available
      fm.PolygonLayer;
      return true;
    } catch (e) {
      LoggingService.error('AirspaceOverlayManager dependency validation failed', e);
      return false;
    }
  }
  
  /// Clear cached aviation data
  void clearCache() {
    _lastBoundsKey = '';

    // Clear debouncing state
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _currentRequestId = null;
    _requestCounter = 0;
    _debouncedRequestsCount = 0;
    _cancelledRequestsCount = 0;

    LoggingService.info('Aviation overlay cache and debouncing state cleared');
  }

  /// Get debouncing performance metrics
  Map<String, dynamic> getDebounceMetrics() {
    return {
      'total_requests': _requestCounter,
      'debounced_requests': _debouncedRequestsCount,
      'cancelled_requests': _cancelledRequestsCount,
      'successful_requests': _requestCounter - _cancelledRequestsCount,
      'debounce_efficiency': _requestCounter > 0 ? _debouncedRequestsCount / _requestCounter : 0.0,
      'current_request_id': _currentRequestId,
      'has_active_timer': _debounceTimer?.isActive ?? false,
    };
  }

  /// Get overlay status for logging/debugging
  Future<Map<String, dynamic>> getOverlayStatus() async {
    final airspaceEnabled = await _openAipService.getAirspaceEnabled();
    final opacity = await _openAipService.getOverlayOpacity();
    final hasApiKey = await _openAipService.hasApiKey();

    return {
      'airspace_enabled': airspaceEnabled,
      'opacity': opacity,
      'has_api_key': hasApiKey,
      'dependencies_valid': validateDependencies(),
      'debounce_metrics': getDebounceMetrics(),
    };
  }

  /// Map numeric type code to string type name
  String? _mapNumericTypeToString(int typeCode) {
    // Reverse mapping from numeric codes to string abbreviations
    const numericToString = {
      0: 'CTA',     // Control Area/Centre
      1: 'A',       // Class A
      2: 'B',       // Class B
      3: 'C',       // Class C
      4: 'CTR',     // Control Zone
      5: 'E',       // Class E
      6: 'A',       // Class A (alternate code)
      7: 'G',       // Class G
      8: 'CTR',     // Control Zone (alternate)
      9: 'TMA',     // Terminal Control Area (alternate)
      10: 'CTA',    // Control Area (primary)
      11: 'R',      // Restricted
      12: 'P',      // Prohibited
      13: 'CTR',    // ATZ (Aerodrome Traffic Zone)
      14: 'D',      // Danger Area
      15: 'R',      // Military Restricted
      16: 'TMA',    // Approach Control
      17: 'CTR',    // Airport Control Zone
      18: 'R',      // Temporary Restricted
      19: 'P',      // Temporary Prohibited
      20: 'D',      // Temporary Danger
      21: 'TMA',    // Terminal Area
      22: 'CTA',    // Control Terminal Area
      23: 'CTA',    // Control Area Extension
      24: 'CTA',    // Control Area Sector
      25: 'CTA',    // Control Area Step
      26: 'CTA',    // Control Terminal Area (CTA A, CTA C1-C7)
    };

    return numericToString[typeCode];
  }

  /// Convert string ICAO class keys to numeric ICAO class keys for airspace filtering
  Map<int, bool> _convertStringClassesToNumeric(Map<String, bool> stringClasses) {
    // Mapping from string ICAO classes to numeric codes used in OpenAIP data
    const stringToNumeric = {
      'A': 0,       // Class A
      'B': 1,       // Class B
      'C': 2,       // Class C
      'D': 3,       // Class D
      'E': 4,       // Class E
      'F': 5,       // Class F
      'G': 6,       // Class G
      'None': 8,    // No ICAO class assigned
    };

    final numericClasses = <int, bool>{};

    stringClasses.forEach((stringClass, enabled) {
      final numericCode = stringToNumeric[stringClass];
      if (numericCode != null) {
        numericClasses[numericCode] = enabled;
      }
    });

    return numericClasses;
  }

  /// Convert string type keys to numeric type keys for airspace filtering
  Map<int, bool> _convertStringTypesToNumeric(Map<String, bool> stringTypes) {
    // Mapping from string abbreviations to numeric codes
    const stringToNumeric = {
      'Unknown': 0,
      'R': 1,       // Restricted (per OpenAIP doc)
      'D': 2,       // Danger (per OpenAIP doc)
      'CTR': 4,     // Control Zone
      'TMA': 6,     // Terminal Control Area (also maps to 7)
      'FIR': 10,    // Flight Information Region
      'CTA': 26,    // Control Area
      // Additional mappings for alternate codes
      'P': 12,      // Prohibited (keeping existing)
      'ATZ': 13,    // Aerodrome Traffic Zone (keeping existing)
    };

    final numericTypes = <int, bool>{};

    stringTypes.forEach((stringType, enabled) {
      final numericCode = stringToNumeric[stringType];
      if (numericCode != null) {
        numericTypes[numericCode] = enabled;

        // Handle special mappings for types that have multiple numeric codes
        if (stringType == 'CTR') {
          // CTR maps to 4, 8, 13, and 17 (various control zone types)
          numericTypes[8] = enabled;
          numericTypes[13] = enabled;  // ATZ
          numericTypes[17] = enabled;
        } else if (stringType == 'TMA') {
          // TMA maps to 6, 7, 9, 16, and 21
          numericTypes[7] = enabled;   // Alternate TMA code
          numericTypes[9] = enabled;
          numericTypes[16] = enabled;
          numericTypes[21] = enabled;
        } else if (stringType == 'R') {
          // Restricted can be 1, 11, 15, 18
          numericTypes[11] = enabled;
          numericTypes[15] = enabled;  // Military Restricted
          numericTypes[18] = enabled;  // Temporary Restricted
        } else if (stringType == 'D') {
          // Danger can be 2, 14, 20
          numericTypes[14] = enabled;
          numericTypes[20] = enabled;  // Temporary Danger
        } else if (stringType == 'P') {
          // Prohibited can be 12, 19
          numericTypes[19] = enabled;  // Temporary Prohibited
        }
      }
    });

    return numericTypes;
  }
}