/// Wind data for a specific location and time
class WindData {
  final double speedKmh;
  final double directionDegrees;
  final double gustsKmh;
  final DateTime timestamp;

  const WindData({
    required this.speedKmh,
    required this.directionDegrees,
    required this.gustsKmh,
    required this.timestamp,
  });

  /// Convert wind direction in degrees to compass direction
  String get compassDirection => _degreesToCompass(directionDegrees);

  /// Check if wind conditions are flyable for a given site
  bool isFlyable(
    List<String> siteDirections,
    double maxSpeed,
    double maxGusts,
  ) {
    // No wind direction data means we can't determine flyability
    if (siteDirections.isEmpty) return false;

    // Check wind speed and gusts limits
    if (speedKmh > maxSpeed || gustsKmh > maxGusts) return false;

    // Light wind (< 1 km/h) - any direction is acceptable
    if (speedKmh < 1.0) return true;

    // Check if wind direction matches any allowed site direction
    // Allow ±22.5° tolerance (half of a compass point)
    return siteDirections.any((dir) => _isDirectionMatch(compassDirection, dir));
  }

  /// Get detailed reason for flyability status
  String getFlyabilityReason(List<String> siteDirections, double maxSpeed, double maxGusts) {
    if (siteDirections.isEmpty) return 'No wind directions defined for site';

    if (speedKmh > maxSpeed) {
      return '${speedKmh.toStringAsFixed(1)} km/h from $compassDirection - too strong (max: ${maxSpeed.toInt()} km/h)';
    }

    if (gustsKmh > maxGusts) {
      return 'Gusts ${gustsKmh.toStringAsFixed(1)} km/h - too strong (max: ${maxGusts.toInt()} km/h)';
    }

    if (speedKmh < 1.0) {
      return '${speedKmh.toStringAsFixed(1)} km/h - light wind, any direction OK';
    }

    final directionMatches = siteDirections.any((dir) => _isDirectionMatch(compassDirection, dir));
    if (directionMatches) {
      return '${speedKmh.toStringAsFixed(1)} km/h from $compassDirection - good direction';
    } else {
      return '${speedKmh.toStringAsFixed(1)} km/h from $compassDirection - wrong direction (needs: ${siteDirections.join(", ")})';
    }
  }

  /// Convert degrees to 16-point compass direction for better accuracy
  static String _degreesToCompass(double degrees) {
    // Normalize degrees to 0-360 range
    final normalizedDegrees = degrees % 360;

    // 16-point compass with 22.5° per direction
    const directions = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW'
    ];

    // Each direction covers 22.5 degrees, offset by 11.25 degrees
    final index = ((normalizedDegrees + 11.25) / 22.5).floor() % 16;

    return directions[index];
  }

  /// Check if two compass directions match with tolerance
  static bool _isDirectionMatch(String windDirection, String siteDirection) {
    // Direct match
    if (windDirection == siteDirection) return true;

    // Map 16-point wind direction to closest 8-point directions for matching
    // This handles cases where wind is ESE but site only has E or SE
    const windTo8Point = {
      'N': ['N'],
      'NNE': ['N', 'NE'],
      'NE': ['NE'],
      'ENE': ['NE', 'E'],
      'E': ['E'],
      'ESE': ['E', 'SE'],
      'SE': ['SE'],
      'SSE': ['SE', 'S'],
      'S': ['S'],
      'SSW': ['S', 'SW'],
      'SW': ['SW'],
      'WSW': ['SW', 'W'],
      'W': ['W'],
      'WNW': ['W', 'NW'],
      'NW': ['NW'],
      'NNW': ['NW', 'N'],
    };

    // Check if wind direction (16-point) matches site direction (8-point)
    final matchingDirections = windTo8Point[windDirection] ?? [];
    return matchingDirections.contains(siteDirection);
  }

  /// Create from JSON (Open-Meteo format)
  factory WindData.fromJson(Map<String, dynamic> json, DateTime timestamp) {
    return WindData(
      speedKmh: (json['wind_speed_10m'] ?? 0.0).toDouble(),
      directionDegrees: (json['wind_direction_10m'] ?? 0.0).toDouble(),
      gustsKmh: (json['wind_gusts_10m'] ?? 0.0).toDouble(),
      timestamp: timestamp,
    );
  }

  /// Convert wind speed from m/s to km/h
  static double msToKmh(double ms) => ms * 3.6;

  /// Convert wind speed from km/h to m/s
  static double kmhToMs(double kmh) => kmh / 3.6;

  @override
  String toString() {
    return 'WindData(speed: ${speedKmh.toStringAsFixed(1)} km/h, '
           'direction: ${directionDegrees.toStringAsFixed(0)}° ($compassDirection), '
           'gusts: ${gustsKmh.toStringAsFixed(1)} km/h)';
  }
}