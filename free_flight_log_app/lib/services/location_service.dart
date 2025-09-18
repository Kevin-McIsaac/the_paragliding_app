import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/site.dart';
import 'logging_service.dart';
import 'database_service.dart';

/// Simplified location service with cleaner fallback strategy
///
/// Reduces complexity by using only essential location features:
/// 1. Current GPS location (with timeout)
/// 2. Last known location (from cache)
/// 3. Perth fallback (for new users)
/// Location status enum for clearer state management
enum LocationStatus {
  available,    // GPS location successfully obtained
  denied,       // Permission denied by user
  disabled,     // Location services disabled
  timeout,      // Location request timed out
  error,        // Other error occurred
  cached,       // Using cached/last known location
  fallback,     // Using fallback location
}

class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();

  LocationService._();

  // Simple in-memory cache
  Position? _cachedPosition;
  DateTime? _cacheTime;
  static const Duration _cacheTimeout = Duration(minutes: 10);

  // Perth coordinates as fallback
  static const double _perthLat = -31.9505;
  static const double _perthLng = 115.8605;

  // SharedPreferences keys
  static const String _lastLatKey = 'last_latitude';
  static const String _lastLngKey = 'last_longitude';
  static const String _lastTimeKey = 'last_time';

  /// Get current location with simplified fallback
  Future<LocationResult> getCurrentLocation() async {
    // Try cached position first
    if (_isCacheValid()) {
      LoggingService.info('Using cached location');
      return LocationResult(_cachedPosition!, LocationStatus.cached);
    }

    // Try current GPS location
    try {
      final hasPermission = await _checkLocationPermission();
      if (!hasPermission) {
        return await _getFallbackLocation(LocationStatus.denied);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8), // Reasonable timeout
        ),
      );

      // Cache the new position
      _cachedPosition = position;
      _cacheTime = DateTime.now();
      await _saveLastKnownLocation(position);

      LoggingService.structured('LOCATION_SUCCESS', {
        'latitude': position.latitude.toStringAsFixed(6),
        'longitude': position.longitude.toStringAsFixed(6),
        'accuracy': position.accuracy.toStringAsFixed(1),
      });

      return LocationResult(position, LocationStatus.available);

    } catch (e) {
      LoggingService.warning('GPS location failed: $e');

      // Try last known location
      final lastKnown = await _getLastKnownLocation();
      if (lastKnown != null) {
        LoggingService.info('Using last known location');
        return LocationResult(lastKnown, LocationStatus.cached);
      }

      // Fall back to Perth
      return await _getFallbackLocation(LocationStatus.error);
    }
  }

  /// Get location for initial app startup (never fails)
  Future<Position> getInitialLocation() async {
    final result = await getCurrentLocation();
    return result.position;
  }

  /// Clear location cache to force fresh GPS lookup
  void clearCache() {
    _cachedPosition = null;
    _cacheTime = null;
    LoggingService.info('Location cache cleared');
  }

  /// Calculate distance between two points using Haversine formula
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Earth's radius in meters

    double lat1Rad = lat1 * (math.pi / 180);
    double lat2Rad = lat2 * (math.pi / 180);
    double deltaLatRad = (lat2 - lat1) * (math.pi / 180);
    double deltaLonRad = (lon2 - lon1) * (math.pi / 180);

    double a = math.sin(deltaLatRad / 2) * math.sin(deltaLatRad / 2) +
               math.cos(lat1Rad) * math.cos(lat2Rad) *
               math.sin(deltaLonRad / 2) * math.sin(deltaLonRad / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c; // Distance in meters
  }

  /// Filter sites by distance from a given position
  List<SiteDistance> filterSitesByDistance(
    List<Site> sites,
    Position position,
    double maxDistanceMeters,
  ) {
    final sitesWithDistance = sites.map((site) {
      final distance = calculateDistance(
        position.latitude,
        position.longitude,
        site.latitude,
        site.longitude,
      );
      return SiteDistance(site: site, distanceMeters: distance);
    }).where((siteDistance) =>
        siteDistance.distanceMeters <= maxDistanceMeters
    ).toList();

    // Sort by distance, closest first
    sitesWithDistance.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return sitesWithDistance;
  }

  /// Format distance for display
  static String formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  // Private helper methods

  bool _isCacheValid() {
    return _cachedPosition != null &&
           _cacheTime != null &&
           DateTime.now().difference(_cacheTime!) < _cacheTimeout;
  }

  Future<bool> _checkLocationPermission() async {
    try {
      // Check if location services are enabled
      if (!await Geolocator.isLocationServiceEnabled()) {
        LoggingService.info('Location services disabled');
        return false;
      }

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          LoggingService.info('Location permission denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        LoggingService.info('Location permission permanently denied');
        return false;
      }

      return true;
    } catch (e) {
      LoggingService.error('Error checking location permission', e);
      return false;
    }
  }

  Future<Position?> _getLastKnownLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_lastLatKey);
      final lng = prefs.getDouble(_lastLngKey);
      final timeMs = prefs.getInt(_lastTimeKey);

      if (lat != null && lng != null && timeMs != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(timeMs);
        final age = DateTime.now().difference(savedTime);

        // Use last known location if less than 7 days old
        if (age.inDays < 7) {
          return Position(
            latitude: lat,
            longitude: lng,
            timestamp: savedTime,
            accuracy: 100.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
        }
      }
    } catch (e) {
      LoggingService.error('Failed to get last known location', e);
    }
    return null;
  }

  Future<void> _saveLastKnownLocation(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lastLatKey, position.latitude);
      await prefs.setDouble(_lastLngKey, position.longitude);
      await prefs.setInt(_lastTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      LoggingService.error('Failed to save last known location', e);
    }
  }

  Future<LocationResult> _getFallbackLocation(LocationStatus status) async {
    // Try user's first flight site as fallback
    try {
      final sites = await DatabaseService.instance.getAllSites();
      if (sites.isNotEmpty) {
        final firstSite = sites.first;
        LoggingService.info('Using first flight site as fallback: ${firstSite.name}');

        final position = Position(
          latitude: firstSite.latitude,
          longitude: firstSite.longitude,
          timestamp: DateTime.now(),
          accuracy: 1000.0, // Large accuracy to indicate fallback
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );

        return LocationResult(position, status);
      }
    } catch (e) {
      LoggingService.error('Failed to get site fallback', e);
    }

    // Final fallback to Perth
    LoggingService.info('Using Perth fallback location');
    final position = Position(
      latitude: _perthLat,
      longitude: _perthLng,
      timestamp: DateTime.now(),
      accuracy: 10000.0, // Very large accuracy for fallback
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );

    return LocationResult(position, LocationStatus.fallback);
  }
}

/// Result class that includes both position and status
class LocationResult {
  final Position position;
  final LocationStatus status;

  const LocationResult(this.position, this.status);

  bool get isGpsLocation => status == LocationStatus.available;
  bool get isCachedLocation => status == LocationStatus.cached;
  bool get isFallbackLocation => status == LocationStatus.fallback;

  String get statusMessage {
    switch (status) {
      case LocationStatus.available:
        return 'GPS location acquired';
      case LocationStatus.cached:
        return 'Using last known location';
      case LocationStatus.denied:
        return 'Location permission denied';
      case LocationStatus.disabled:
        return 'Location services disabled';
      case LocationStatus.timeout:
        return 'Location request timed out';
      case LocationStatus.error:
        return 'Location error occurred';
      case LocationStatus.fallback:
        return 'Using fallback location';
    }
  }
}

/// Data class to hold a site with its calculated distance
class SiteDistance {
  final Site site;
  final double distanceMeters;

  const SiteDistance({
    required this.site,
    required this.distanceMeters,
  });

  String get formattedDistance => LocationService.formatDistance(distanceMeters);
}