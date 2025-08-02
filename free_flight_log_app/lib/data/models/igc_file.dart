import 'dart:math';

/// IGC file data model
class IgcFile {
  final DateTime date;
  final String pilot;
  final String gliderType;
  final String gliderID;
  final List<IgcPoint> trackPoints;
  final Map<String, String> headers;
  
  IgcFile({
    required this.date,
    required this.pilot,
    required this.gliderType,
    required this.gliderID,
    required this.trackPoints,
    required this.headers,
  });

  /// Get launch time from first track point
  DateTime get launchTime => trackPoints.isNotEmpty 
      ? trackPoints.first.timestamp 
      : date;

  /// Get landing time from last track point
  DateTime get landingTime => trackPoints.isNotEmpty 
      ? trackPoints.last.timestamp 
      : date;

  /// Calculate flight duration in minutes
  int get duration => landingTime.difference(launchTime).inMinutes;

  /// Find maximum altitude
  double get maxAltitude => trackPoints.isEmpty 
      ? 0 
      : trackPoints.map((p) => p.gpsAltitude).reduce(max).toDouble();

  /// Calculate total distance in kilometers
  double calculateDistance() {
    if (trackPoints.length < 2) return 0;
    
    double totalDistance = 0;
    for (int i = 1; i < trackPoints.length; i++) {
      totalDistance += _haversineDistance(
        trackPoints[i - 1], 
        trackPoints[i]
      );
    }
    return totalDistance;
  }

  /// Calculate climb rates
  Map<String, double> calculateClimbRates() {
    if (trackPoints.length < 2) {
      return {'maxClimb': 0, 'maxSink': 0};
    }

    double maxClimb = 0;
    double maxSink = 0;

    for (int i = 1; i < trackPoints.length; i++) {
      final timeDiff = trackPoints[i].timestamp
          .difference(trackPoints[i - 1].timestamp)
          .inSeconds;
      
      if (timeDiff > 0) {
        final altDiff = trackPoints[i].gpsAltitude - 
                        trackPoints[i - 1].gpsAltitude;
        final climbRate = altDiff / timeDiff; // m/s
        
        if (climbRate > maxClimb) maxClimb = climbRate;
        if (climbRate < maxSink) maxSink = climbRate;
      }
    }

    return {
      'maxClimb': maxClimb,
      'maxSink': maxSink.abs(),
    };
  }

  /// Calculate distance between two points using Haversine formula
  double _haversineDistance(IgcPoint p1, IgcPoint p2) {
    const double earthRadius = 6371; // km
    
    final lat1Rad = p1.latitude * pi / 180;
    final lat2Rad = p2.latitude * pi / 180;
    final deltaLat = (p2.latitude - p1.latitude) * pi / 180;
    final deltaLon = (p2.longitude - p1.longitude) * pi / 180;

    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLon / 2) * sin(deltaLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }

  /// Get launch site coordinates
  IgcPoint? get launchSite => trackPoints.isNotEmpty ? trackPoints.first : null;

  /// Get landing site coordinates  
  IgcPoint? get landingSite => trackPoints.isNotEmpty ? trackPoints.last : null;
}

/// Single track point in IGC file
class IgcPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final int pressureAltitude;
  final int gpsAltitude;
  final bool isValid;
  
  IgcPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.pressureAltitude,
    required this.gpsAltitude,
    required this.isValid,
  });
}