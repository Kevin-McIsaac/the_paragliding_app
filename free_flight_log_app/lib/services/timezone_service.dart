import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:math';

class TimezoneService {
  static bool _initialized = false;
  
  static void initialize() {
    if (!_initialized) {
      tz.initializeTimeZones();
      _initialized = true;
    }
  }
  
  /// Get timezone from GPS coordinates
  /// Returns timezone identifier (e.g., "Europe/Zurich") or null if not found
  static String? getTimezoneFromCoordinates(double latitude, double longitude) {
    initialize();
    
    // Define a comprehensive list of timezone locations with their coordinates
    // This is a simplified approach - in production, you might use a more complete database
    final timezoneLocations = [
      // Europe
      {'name': 'Europe/London', 'lat': 51.5074, 'lon': -0.1278, 'radius': 500},
      {'name': 'Europe/Paris', 'lat': 48.8566, 'lon': 2.3522, 'radius': 500},
      {'name': 'Europe/Berlin', 'lat': 52.5200, 'lon': 13.4050, 'radius': 500},
      {'name': 'Europe/Zurich', 'lat': 47.3769, 'lon': 8.5417, 'radius': 300},
      {'name': 'Europe/Vienna', 'lat': 48.2082, 'lon': 16.3738, 'radius': 300},
      {'name': 'Europe/Rome', 'lat': 41.9028, 'lon': 12.4964, 'radius': 500},
      {'name': 'Europe/Madrid', 'lat': 40.4168, 'lon': -3.7038, 'radius': 500},
      {'name': 'Europe/Stockholm', 'lat': 59.3293, 'lon': 18.0686, 'radius': 500},
      {'name': 'Europe/Oslo', 'lat': 59.9139, 'lon': 10.7522, 'radius': 400},
      {'name': 'Europe/Moscow', 'lat': 55.7558, 'lon': 37.6173, 'radius': 800},
      
      // North America
      {'name': 'America/New_York', 'lat': 40.7128, 'lon': -74.0060, 'radius': 500},
      {'name': 'America/Chicago', 'lat': 41.8781, 'lon': -87.6298, 'radius': 500},
      {'name': 'America/Denver', 'lat': 39.7392, 'lon': -104.9903, 'radius': 500},
      {'name': 'America/Los_Angeles', 'lat': 34.0522, 'lon': -118.2437, 'radius': 500},
      {'name': 'America/Vancouver', 'lat': 49.2827, 'lon': -123.1207, 'radius': 400},
      {'name': 'America/Toronto', 'lat': 43.6532, 'lon': -79.3832, 'radius': 400},
      {'name': 'America/Mexico_City', 'lat': 19.4326, 'lon': -99.1332, 'radius': 600},
      
      // Asia
      {'name': 'Asia/Tokyo', 'lat': 35.6762, 'lon': 139.6503, 'radius': 500},
      {'name': 'Asia/Shanghai', 'lat': 31.2304, 'lon': 121.4737, 'radius': 800},
      {'name': 'Asia/Hong_Kong', 'lat': 22.3193, 'lon': 114.1694, 'radius': 300},
      {'name': 'Asia/Singapore', 'lat': 1.3521, 'lon': 103.8198, 'radius': 200},
      {'name': 'Asia/Dubai', 'lat': 25.2048, 'lon': 55.2708, 'radius': 500},
      {'name': 'Asia/Kolkata', 'lat': 22.5726, 'lon': 88.3639, 'radius': 800},
      {'name': 'Asia/Bangkok', 'lat': 13.7563, 'lon': 100.5018, 'radius': 600},
      {'name': 'Asia/Seoul', 'lat': 37.5665, 'lon': 126.9780, 'radius': 400},
      
      // Australia/Oceania
      {'name': 'Australia/Sydney', 'lat': -33.8688, 'lon': 151.2093, 'radius': 500},
      {'name': 'Australia/Melbourne', 'lat': -37.8136, 'lon': 144.9631, 'radius': 400},
      {'name': 'Australia/Brisbane', 'lat': -27.4698, 'lon': 153.0251, 'radius': 400},
      {'name': 'Australia/Perth', 'lat': -31.9505, 'lon': 115.8605, 'radius': 500},
      {'name': 'Pacific/Auckland', 'lat': -36.8485, 'lon': 174.7633, 'radius': 400},
      
      // South America
      {'name': 'America/Sao_Paulo', 'lat': -23.5505, 'lon': -46.6333, 'radius': 600},
      {'name': 'America/Buenos_Aires', 'lat': -34.6037, 'lon': -58.3816, 'radius': 500},
      {'name': 'America/Santiago', 'lat': -33.4489, 'lon': -70.6693, 'radius': 500},
      {'name': 'America/Lima', 'lat': -12.0464, 'lon': -77.0428, 'radius': 500},
      {'name': 'America/Bogota', 'lat': 4.7110, 'lon': -74.0721, 'radius': 500},
      
      // Africa
      {'name': 'Africa/Cairo', 'lat': 30.0444, 'lon': 31.2357, 'radius': 500},
      {'name': 'Africa/Johannesburg', 'lat': -26.2041, 'lon': 28.0473, 'radius': 500},
      {'name': 'Africa/Lagos', 'lat': 6.5244, 'lon': 3.3792, 'radius': 400},
      {'name': 'Africa/Nairobi', 'lat': -1.2921, 'lon': 36.8219, 'radius': 400},
    ];
    
    // Find the closest timezone location
    double minDistance = double.infinity;
    String? closestTimezone;
    
    for (var location in timezoneLocations) {
      final distance = _calculateDistance(
        latitude,
        longitude,
        location['lat'] as double,
        location['lon'] as double,
      );
      
      // Check if this location is within its radius and is the closest
      if (distance < (location['radius'] as int) && distance < minDistance) {
        minDistance = distance;
        closestTimezone = location['name'] as String;
      }
    }
    
    // If no timezone found within radius, fall back to basic longitude-based estimation
    if (closestTimezone == null) {
      closestTimezone = _estimateTimezoneFromLongitude(longitude, latitude);
    }
    
    return closestTimezone;
  }
  
  /// Calculate distance between two coordinates in kilometers
  static double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // km
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }
  
  static double _toRadians(double degrees) => degrees * pi / 180;
  
  /// Estimate timezone based on longitude (fallback method)
  static String _estimateTimezoneFromLongitude(double longitude, double latitude) {
    // Very rough estimation based on longitude
    // This is a simplified approach for when exact location matching fails
    
    // Europe (longitude -10 to 30, latitude 35 to 70)
    if (latitude > 35 && latitude < 70) {
      if (longitude > -10 && longitude < 0) return 'Europe/London';
      if (longitude >= 0 && longitude < 10) return 'Europe/Paris';
      if (longitude >= 10 && longitude < 20) return 'Europe/Berlin';
      if (longitude >= 20 && longitude < 30) return 'Europe/Athens';
    }
    
    // North America (longitude -130 to -60, latitude 25 to 60)
    if (latitude > 25 && latitude < 60) {
      if (longitude > -130 && longitude < -110) return 'America/Los_Angeles';
      if (longitude >= -110 && longitude < -100) return 'America/Denver';
      if (longitude >= -100 && longitude < -85) return 'America/Chicago';
      if (longitude >= -85 && longitude < -70) return 'America/New_York';
    }
    
    // Asia
    if (longitude > 60 && longitude < 150) {
      if (longitude < 80) return 'Asia/Dubai';
      if (longitude < 90) return 'Asia/Kolkata';
      if (longitude < 110) return 'Asia/Bangkok';
      if (longitude < 130) return 'Asia/Shanghai';
      return 'Asia/Tokyo';
    }
    
    // Australia
    if (latitude < -20 && longitude > 110 && longitude < 160) {
      if (longitude < 130) return 'Australia/Perth';
      if (longitude < 145) return 'Australia/Adelaide';
      return 'Australia/Sydney';
    }
    
    // Default to UTC
    return 'UTC';
  }
  
  /// Convert timezone identifier to offset string (e.g., "+01:00")
  static String? getOffsetStringFromTimezone(String timezoneId, DateTime dateTime) {
    try {
      initialize();
      final location = tz.getLocation(timezoneId);
      final tzDateTime = tz.TZDateTime.from(dateTime, location);
      final offset = tzDateTime.timeZoneOffset;
      
      final hours = offset.inHours.abs();
      final minutes = (offset.inMinutes.abs() % 60);
      final sign = offset.isNegative ? '-' : '+';
      
      return '$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    } catch (e) {
      print('Error getting offset for timezone $timezoneId: $e');
      return null;
    }
  }
}