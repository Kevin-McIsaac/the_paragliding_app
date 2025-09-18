import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import '../services/logging_service.dart';
import '../services/airspace_geojson_service.dart';
import '../data/models/airspace_enums.dart';

/// Container for airspace polygon with associated data
class AirspacePolygonData {
  final List<LatLng> points;
  final AirspaceData airspaceData;

  AirspacePolygonData({
    required this.points,
    required this.airspaceData,
  });
}

/// Service for identifying airspace at specific geographic points
/// Uses point-in-polygon ray casting algorithm for accurate detection
class AirspaceIdentificationService {
  static AirspaceIdentificationService? _instance;
  static AirspaceIdentificationService get instance => _instance ??= AirspaceIdentificationService._();

  AirspaceIdentificationService._();

  // Cache of loaded airspace polygons with their metadata
  List<AirspacePolygonData> _airspacePolygons = [];
  String? _lastBoundsKey;

  /// Update the cached airspace polygon data
  void updateAirspacePolygons(List<AirspacePolygonData> polygons, String boundsKey) {
    _airspacePolygons = polygons;
    _lastBoundsKey = boundsKey;

    LoggingService.structured('AIRSPACE_POLYGONS_UPDATED', {
      'polygon_count': polygons.length,
      'bounds_key': boundsKey,
    });
  }

  /// Identify all airspaces containing the given point
  List<AirspaceData> identifyAirspacesAtPoint(LatLng point) {
    final start = DateTime.now();
    final containingAirspaces = <AirspaceData>[];

    for (final polygonData in _airspacePolygons) {
      if (_pointInPolygon(point, polygonData.points)) {
        containingAirspaces.add(polygonData.airspaceData);
      }
    }

    // Removed verbose AIRSPACE_IDENTIFICATION logging to reduce noise
    // Only log if identification is very slow (>100ms)
    final duration = DateTime.now().difference(start);
    if (duration.inMilliseconds > 100) {
      LoggingService.structured('AIRSPACE_IDENTIFICATION_SLOW', {
        'point': '${point.latitude},${point.longitude}',
        'polygons_checked': _airspacePolygons.length,
        'airspaces_found': containingAirspaces.length,
        'duration_ms': duration.inMicroseconds / 1000,
        'airspace_types': containingAirspaces.map((a) => a.type).toList(),
      });
    }

    // Sort by lower altitude first, then upper altitude if lower altitudes are equal
    containingAirspaces.sort((a, b) {
      int lowerCompare = a.getLowerAltitudeInFeet().compareTo(b.getLowerAltitudeInFeet());
      if (lowerCompare != 0) return lowerCompare;
      return a.getUpperAltitudeInFeet().compareTo(b.getUpperAltitudeInFeet());
    });

    return containingAirspaces;
  }


  /// Point-in-polygon test using ray casting algorithm
  /// Robust implementation handling edge cases and precision issues
  bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    bool inside = false;
    int j = polygon.length - 1;

    for (int i = 0; i < polygon.length; i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      // Ray casting: count intersections with horizontal ray to the right
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
      j = i;
    }

    return inside;
  }

  /// Alternative point-in-polygon using winding number (more robust for complex polygons)
  /// Currently not used but kept for reference/future enhancement
  // ignore: unused_element
  bool _pointInPolygonWindingNumber(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;

    double windingNumber = 0.0;

    for (int i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];

      if (current.latitude <= point.latitude) {
        if (next.latitude > point.latitude) {
          // Upward crossing
          if (_isLeft(current, next, point) > 0) {
            windingNumber += 1;
          }
        }
      } else {
        if (next.latitude <= point.latitude) {
          // Downward crossing
          if (_isLeft(current, next, point) < 0) {
            windingNumber -= 1;
          }
        }
      }
    }

    return windingNumber != 0;
  }

  /// Helper for winding number algorithm
  double _isLeft(LatLng p0, LatLng p1, LatLng point) {
    return (p1.longitude - p0.longitude) * (point.latitude - p0.latitude) -
           (point.longitude - p0.longitude) * (p1.latitude - p0.latitude);
  }

  /// Calculate distance from point to polygon edge (for future enhancements)
  double calculateDistanceToEdge(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 2) return double.infinity;

    double minDistance = double.infinity;

    for (int i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];

      final distance = _distanceToLineSegment(point, current, next);
      minDistance = math.min(minDistance, distance);
    }

    return minDistance;
  }

  /// Calculate distance from point to line segment
  double _distanceToLineSegment(LatLng point, LatLng start, LatLng end) {
    const Distance distance = Distance();

    // Convert to meters for calculation
    final segmentLength = distance.as(LengthUnit.Meter, start, end);
    if (segmentLength == 0) return distance.as(LengthUnit.Meter, point, start);

    // Project point onto line segment
    final dx = end.longitude - start.longitude;
    final dy = end.latitude - start.latitude;

    final t = math.max(0, math.min(1,
      ((point.longitude - start.longitude) * dx + (point.latitude - start.latitude) * dy) /
      (dx * dx + dy * dy)
    ));

    // Find closest point on segment
    final closestPoint = LatLng(
      start.latitude + t * dy,
      start.longitude + t * dx,
    );

    return distance.as(LengthUnit.Meter, point, closestPoint);
  }

  /// Clear cached data
  void clearCache() {
    _airspacePolygons.clear();
    _lastBoundsKey = null;
    LoggingService.info('Airspace identification cache cleared');
  }

  /// Get cache statistics for debugging
  Map<String, dynamic> getCacheStats() {
    final typeStats = <AirspaceType, int>{};
    for (final polygon in _airspacePolygons) {
      final type = polygon.airspaceData.type;
      typeStats[type] = (typeStats[type] ?? 0) + 1;
    }

    return {
      'polygon_count': _airspacePolygons.length,
      'bounds_key': _lastBoundsKey,
      'type_distribution': typeStats,
    };
  }

  /// Get polygon points for a specific airspace (for highlighting)
  /// Returns null if airspace not found in cache
  List<LatLng>? getPolygonForAirspace(AirspaceData airspace) {
    // Find matching airspace in cache by name and type
    // (Can't use object equality as these are different instances)
    for (final polygon in _airspacePolygons) {
      if (polygon.airspaceData.name == airspace.name &&
          polygon.airspaceData.type == airspace.type) {
        return polygon.points;
      }
    }
    return null;
  }
}