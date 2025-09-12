import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import '../data/models/site.dart';
import 'logging_service.dart';

class LocationService {
  static LocationService? _instance;
  static LocationService get instance => _instance ??= LocationService._();
  
  LocationService._();
  
  Position? _lastKnownPosition;
  DateTime? _lastPositionTime;
  static const Duration _positionCacheTimeout = Duration(minutes: 5);
  
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
        timeLimit: const Duration(seconds: 10),
      );
      
      stopwatch.stop();
      
      _lastKnownPosition = position;
      _lastPositionTime = DateTime.now();
      
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