import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/site.dart';
import 'logging_service.dart';
import 'database_service.dart';

class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();
  
  LocationService._();
  
  Position? _lastKnownPosition;
  DateTime? _lastPositionTime;
  static const Duration _positionCacheTimeout = Duration(minutes: 5);
  
  // Perth, Western Australia coordinates as fallback
  static const double _perthLatitude = -31.9505;
  static const double _perthLongitude = 115.8605;
  
  // SharedPreferences keys for persistent location storage
  static const String _lastLatKey = 'last_known_latitude';
  static const String _lastLngKey = 'last_known_longitude';
  static const String _lastTimeKey = 'last_known_time';
  
  /// Check if location services are enabled and permissions are granted
  Future<bool> isLocationAvailable() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        LoggingService.info('Location services are disabled');
        return false;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        LoggingService.info('Location permission denied, requesting permission');
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          LoggingService.info('Location permission denied by user');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        LoggingService.info('Location permission permanently denied');
        return false;
      }

      return true;
    } catch (e, stackTrace) {
      LoggingService.error('Error checking location availability', e, stackTrace);
      return false;
    }
  }

  /// Get current device position with caching
  Future<Position?> getCurrentPosition() async {
    try {
      // Return cached position if still valid
      if (_lastKnownPosition != null && 
          _lastPositionTime != null &&
          DateTime.now().difference(_lastPositionTime!) < _positionCacheTimeout) {
        LoggingService.info('Using cached position');
        return _lastKnownPosition;
      }

      if (!await isLocationAvailable()) {
        LoggingService.info('Location not available');
        return null;
      }

      LoggingService.structured('LOCATION_REQUEST', {
        'has_cached_position': _lastKnownPosition != null,
        'cache_age_seconds': _lastPositionTime != null 
            ? DateTime.now().difference(_lastPositionTime!).inSeconds
            : null,
      });

      final stopwatch = Stopwatch()..start();
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      );
      
      stopwatch.stop();
      
      _lastKnownPosition = position;
      _lastPositionTime = DateTime.now();
      
      // Save position to persistent storage
      await _savePositionToPersistentStorage(position);
      
      LoggingService.performance(
        'Get Current Position',
        Duration(milliseconds: stopwatch.elapsedMilliseconds),
        'location acquired',
      );
      
      LoggingService.structured('LOCATION_ACQUIRED', {
        'latitude': position.latitude.toStringAsFixed(6),
        'longitude': position.longitude.toStringAsFixed(6),
        'accuracy': position.accuracy.toStringAsFixed(1),
        'duration_ms': stopwatch.elapsedMilliseconds,
      });

      return position;
    } catch (e, stackTrace) {
      LoggingService.error('Error getting current position', e, stackTrace);
      return null;
    }
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
    final stopwatch = Stopwatch()..start();
    
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
    
    stopwatch.stop();
    
    LoggingService.performance(
      'Filter Sites by Distance',
      Duration(milliseconds: stopwatch.elapsedMilliseconds),
      '${sitesWithDistance.length} sites within ${maxDistanceMeters / 1000}km',
    );
    
    LoggingService.structured('SITES_FILTERED_BY_DISTANCE', {
      'total_sites': sites.length,
      'filtered_sites': sitesWithDistance.length,
      'max_distance_km': maxDistanceMeters / 1000,
      'filter_time_ms': stopwatch.elapsedMilliseconds,
      'position': {
        'lat': position.latitude.toStringAsFixed(6),
        'lng': position.longitude.toStringAsFixed(6),
      },
    });

    return sitesWithDistance;
  }

  /// Get sites within a radius, sorted by distance
  Future<List<SiteDistance>> getNearbySites(
    List<Site> allSites,
    double radiusKm,
  ) async {
    final position = await getCurrentPosition();
    if (position == null) {
      LoggingService.info('No position available for nearby sites');
      return [];
    }

    return filterSitesByDistance(allSites, position, radiusKm * 1000);
  }

  /// Format distance for display
  static String formatDistance(double distanceMeters) {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    } else {
      return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// Clear cached position (useful for forcing fresh location)
  void clearCache() {
    _lastKnownPosition = null;
    _lastPositionTime = null;
    LoggingService.info('Location cache cleared');
  }

  /// Save position to persistent storage
  Future<void> _savePositionToPersistentStorage(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_lastLatKey, position.latitude);
      await prefs.setDouble(_lastLngKey, position.longitude);
      await prefs.setInt(_lastTimeKey, DateTime.now().millisecondsSinceEpoch);
      LoggingService.info('Position saved to persistent storage');
    } catch (e) {
      LoggingService.error('Failed to save position to persistent storage', e);
    }
  }

  /// Load position from persistent storage
  Future<Position?> _loadPositionFromPersistentStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_lastLatKey);
      final lng = prefs.getDouble(_lastLngKey);
      final timeMs = prefs.getInt(_lastTimeKey);
      
      if (lat != null && lng != null && timeMs != null) {
        final savedTime = DateTime.fromMillisecondsSinceEpoch(timeMs);
        final age = DateTime.now().difference(savedTime);
        
        // Only use persistent location if it's less than 7 days old
        if (age.inDays < 7) {
          LoggingService.info('Loaded position from persistent storage (${age.inHours}h old)');
          return Position(
            latitude: lat,
            longitude: lng,
            timestamp: savedTime,
            accuracy: 100.0, // Default accuracy for persistent position
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
      LoggingService.error('Failed to load position from persistent storage', e);
    }
    return null;
  }

  /// Get last known position or Perth fallback (synchronous)
  Future<Position> getLastKnownOrDefault() async {
    // Try memory cache first
    if (_lastKnownPosition != null && 
        _lastPositionTime != null &&
        DateTime.now().difference(_lastPositionTime!) < _positionCacheTimeout) {
      LoggingService.info('Using cached position from memory');
      return _lastKnownPosition!;
    }
    
    // Try persistent storage
    final persistentPosition = await _loadPositionFromPersistentStorage();
    if (persistentPosition != null) {
      return persistentPosition;
    }
    
    // Try first site in database
    try {
      final sites = await DatabaseService.instance.getAllSites();
      if (sites.isNotEmpty) {
        final firstSite = sites.first;
        LoggingService.info('Using first site from database: ${firstSite.name}');
        return Position(
          latitude: firstSite.latitude,
          longitude: firstSite.longitude,
          timestamp: DateTime.now(),
          accuracy: 500.0, // Moderate accuracy to indicate this is from database
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
      }
    } catch (e) {
      LoggingService.error('Failed to get first site from database', e);
    }
    
    // Final fallback to Perth, Western Australia
    LoggingService.info('Using Perth fallback coordinates');
    return Position(
      latitude: _perthLatitude,
      longitude: _perthLongitude,
      timestamp: DateTime.now(),
      accuracy: 1000.0, // Large accuracy to indicate this is a fallback
      altitude: 0.0,
      altitudeAccuracy: 0.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
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