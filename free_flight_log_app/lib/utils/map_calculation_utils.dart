import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart';
import '../data/models/igc_file.dart';

/// Shared utilities for map-related calculations
/// Consolidates common calculation methods used across different map widgets
class MapCalculationUtils {
  static const double earthRadiusMeters = 6371000.0;
  static const double earthRadiusKm = 6371.0;
  static const double metersPerDegreeLat = 111320.0;

  /// Calculate distance between two LatLng points using Haversine formula
  /// Returns distance in meters
  static double haversineDistance(LatLng point1, LatLng point2) {
    final lat1Rad = point1.latitude * (math.pi / 180);
    final lat2Rad = point2.latitude * (math.pi / 180);
    final deltaLat = (point2.latitude - point1.latitude) * (math.pi / 180);
    final deltaLng = (point2.longitude - point1.longitude) * (math.pi / 180);

    final a = math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1Rad) * math.cos(lat2Rad) *
        math.sin(deltaLng / 2) * math.sin(deltaLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Calculate distance between two LatLng points using Haversine formula
  /// Returns distance in kilometers
  static double haversineDistanceKm(LatLng point1, LatLng point2) {
    return haversineDistance(point1, point2) / 1000.0;
  }

  /// Calculate simple distance between two lat/lng points using Pythagorean formula
  /// For small distances (GPS points), Earth curvature correction is negligible
  /// Returns distance in meters
  static double simpleDistance(double lat1, double lng1, double lat2, double lng2) {
    // Convert degrees to approximate meters using first point's latitude for longitude correction
    final metersPerDegreeLng = metersPerDegreeLat * math.cos(lat1 * math.pi / 180);

    final deltaLat = (lat2 - lat1) * metersPerDegreeLat;
    final deltaLng = (lng2 - lng1) * metersPerDegreeLng;

    return math.sqrt(deltaLat * deltaLat + deltaLng * deltaLng);
  }

  /// Calculate climb rate between two IGC points
  /// Returns climb rate in m/s
  static double calculateClimbRate(IgcPoint point1, IgcPoint point2) {
    final timeDiff = point2.timestamp.difference(point1.timestamp).inSeconds;
    if (timeDiff <= 0) return 0.0;
    final altitudeDiff = point2.gpsAltitude - point1.gpsAltitude;
    return altitudeDiff / timeDiff;
  }

  /// Calculate average climb rate over a time window
  /// Returns average climb rate in m/s
  static double calculateAverageClimbRate(
    IgcPoint currentPoint,
    int windowSeconds, {
    List<IgcPoint>? trackPoints,
    int? currentIndex,
  }) {
    if (currentPoint.parentFile == null || currentPoint.pointIndex == null) {
      return currentPoint.climbRate;
    }

    final tracks = trackPoints ?? currentPoint.parentFile!.trackPoints;
    final index = currentIndex ?? currentPoint.pointIndex!;

    if (index >= tracks.length || index == 0) {
      return currentPoint.climbRate; // Fallback to instantaneous for first point
    }

    // Find the first point in the time window (looking backwards from current point)
    IgcPoint? firstInWindow;
    for (int i = index - 1; i >= 0; i--) {
      final timeDiff = currentPoint.timestamp.difference(tracks[i].timestamp).inSeconds;
      if (timeDiff >= windowSeconds) {
        firstInWindow = tracks[i];
        break;
      }
    }

    if (firstInWindow == null) {
      return currentPoint.climbRate; // Not enough data for window
    }

    return calculateClimbRate(firstInWindow, currentPoint);
  }

  /// Calculate bounds for a list of track points with optional padding
  /// Returns LatLngBounds that encompasses all points
  static LatLngBounds calculateBounds(
    List<IgcPoint> trackPoints, {
    double padding = 0.005, // Default padding in degrees
  }) {
    if (trackPoints.isEmpty) {
      // Return default bounds if no points
      return LatLngBounds(
        const LatLng(46.9480, 7.4474),
        const LatLng(46.9580, 7.4574),
      );
    }

    double minLat = trackPoints.first.latitude;
    double maxLat = trackPoints.first.latitude;
    double minLng = trackPoints.first.longitude;
    double maxLng = trackPoints.first.longitude;

    for (final point in trackPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      LatLng(minLat - padding, minLng - padding),
      LatLng(maxLat + padding, maxLng + padding),
    );
  }

  /// Calculate bounds for a list of LatLng points with optional padding
  /// Returns LatLngBounds that encompasses all points
  static LatLngBounds calculateLatLngBounds(
    List<LatLng> points, {
    double padding = 0.005, // Default padding in degrees
  }) {
    if (points.isEmpty) {
      // Return default bounds if no points
      return LatLngBounds(
        const LatLng(46.9480, 7.4474),
        const LatLng(46.9580, 7.4574),
      );
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    return LatLngBounds(
      LatLng(minLat - padding, minLng - padding),
      LatLng(maxLat + padding, maxLng + padding),
    );
  }

  /// Find the closest track point to a given position
  /// Returns the index of the closest point, or -1 if no points
  static int findClosestTrackPoint(LatLng position, List<IgcPoint> trackPoints) {
    if (trackPoints.isEmpty) return -1;

    int closestIndex = 0;
    double minDistance = haversineDistance(
      position,
      LatLng(trackPoints[0].latitude, trackPoints[0].longitude)
    );

    for (int i = 1; i < trackPoints.length; i++) {
      final distance = haversineDistance(
        position,
        LatLng(trackPoints[i].latitude, trackPoints[i].longitude)
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }

    return closestIndex;
  }

  /// Calculate bearing from point1 to point2
  /// Returns bearing in degrees (0-360)
  static double calculateBearing(LatLng point1, LatLng point2) {
    final lat1Rad = point1.latitude * (math.pi / 180);
    final lat2Rad = point2.latitude * (math.pi / 180);
    final deltaLngRad = (point2.longitude - point1.longitude) * (math.pi / 180);

    final x = math.sin(deltaLngRad) * math.cos(lat2Rad);
    final y = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(deltaLngRad);

    final bearing = math.atan2(x, y);
    return (bearing * 180 / math.pi + 360) % 360;
  }

  /// Calculate the midpoint between two LatLng points
  static LatLng calculateMidpoint(LatLng point1, LatLng point2) {
    return LatLng(
      (point1.latitude + point2.latitude) / 2,
      (point1.longitude + point2.longitude) / 2,
    );
  }

  /// Format distance for display
  static String formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Format altitude for display
  static String formatAltitude(double altitudeMeters) {
    return '${altitudeMeters.toStringAsFixed(0)}m';
  }

  /// Convert meters to feet
  static double metersToFeet(double meters) {
    return meters * 3.28084;
  }

  /// Convert feet to meters
  static double feetToMeters(double feet) {
    return feet / 3.28084;
  }
}