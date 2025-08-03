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

  /// Calculate total ground track distance in kilometers (following the actual flight path)
  double calculateGroundTrackDistance() {
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

  /// Calculate straight-line distance from launch to landing in kilometers
  double calculateLaunchToLandingDistance() {
    if (trackPoints.length < 2) return 0;
    
    return _haversineDistance(trackPoints.first, trackPoints.last);
  }

  /// Legacy method - use calculateGroundTrackDistance() instead
  @deprecated
  double calculateDistance() => calculateGroundTrackDistance();

  /// Calculate instantaneous climb rates (between consecutive points)
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
        // Use pressure altitude for climb rate if available (more accurate for vertical speed)
        final altDiff = (trackPoints[i].pressureAltitude > 0 && trackPoints[i - 1].pressureAltitude > 0)
            ? trackPoints[i].pressureAltitude - trackPoints[i - 1].pressureAltitude
            : trackPoints[i].gpsAltitude - trackPoints[i - 1].gpsAltitude;
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

  /// Calculate maximum 15-second average climb rates
  Map<String, double> calculate15SecondMaxClimbRates() {
    if (trackPoints.length < 2) {
      return {'maxClimb15Sec': 0, 'maxSink15Sec': 0};
    }

    final fifteenSecRates = calculate15SecondClimbRates();
    
    if (fifteenSecRates.isEmpty) {
      return {'maxClimb15Sec': 0, 'maxSink15Sec': 0};
    }
    
    double maxClimb15Sec = 0;
    double maxSink15Sec = 0;

    for (final rate in fifteenSecRates) {
      if (rate > maxClimb15Sec) maxClimb15Sec = rate;
      if (rate < maxSink15Sec) maxSink15Sec = rate;
    }

    return {
      'maxClimb15Sec': maxClimb15Sec,
      'maxSink15Sec': maxSink15Sec.abs(),
    };
  }
  
  /// Deprecated: Use calculate15SecondMaxClimbRates instead
  @deprecated
  Map<String, double> calculate5SecondMaxClimbRates() {
    final result = calculate15SecondMaxClimbRates();
    return {
      'maxClimb5Sec': result['maxClimb15Sec'] ?? 0,
      'maxSink5Sec': result['maxSink15Sec'] ?? 0,
    };
  }
  
  /// Deprecated: Use calculate15SecondClimbRates instead
  @deprecated
  List<double> calculate5SecondClimbRates() {
    return calculate15SecondClimbRates();
  }

  /// Calculate instantaneous climb rates for each point
  List<double> calculateInstantaneousClimbRates() {
    if (trackPoints.length < 2) return [];

    final climbRates = <double>[];
    
    // First point has no previous point, so climb rate is 0
    climbRates.add(0.0);

    for (int i = 1; i < trackPoints.length; i++) {
      final timeDiff = trackPoints[i].timestamp
          .difference(trackPoints[i - 1].timestamp)
          .inSeconds;
      
      if (timeDiff > 0) {
        final altDiff = (trackPoints[i].pressureAltitude > 0 && trackPoints[i - 1].pressureAltitude > 0)
            ? trackPoints[i].pressureAltitude - trackPoints[i - 1].pressureAltitude
            : trackPoints[i].gpsAltitude - trackPoints[i - 1].gpsAltitude;
        final climbRate = altDiff / timeDiff; // m/s
        climbRates.add(climbRate);
      } else {
        climbRates.add(0.0);
      }
    }

    return climbRates;
  }

  /// Calculate 15-second average climb rates for each point
  List<double> calculate15SecondClimbRates() {
    if (trackPoints.length < 2) return [];

    final climbRates = <double>[];
    
    for (int i = 0; i < trackPoints.length; i++) {
      // Look for points within a 15-second window centered on current point
      // Or if at edges, use available points
      final currentTime = trackPoints[i].timestamp;
      
      // Determine window bounds
      final windowStart = currentTime.subtract(const Duration(milliseconds: 7500));
      final windowEnd = currentTime.add(const Duration(milliseconds: 7500));
      
      // Find first and last points within window
      IgcPoint? firstInWindow;
      IgcPoint? lastInWindow;
      
      for (final point in trackPoints) {
        final pointTime = point.timestamp;
        
        // Check if point is within window
        if (!pointTime.isBefore(windowStart) && !pointTime.isAfter(windowEnd)) {
          firstInWindow ??= point;
          lastInWindow = point;
        }
      }
      
      // If we don't have at least 2 distinct points, try expanding the window
      if (firstInWindow == null || lastInWindow == null || firstInWindow == lastInWindow) {
        // Use instantaneous rate for this point as fallback
        if (i > 0) {
          final timeDiff = (trackPoints[i].timestamp.millisecondsSinceEpoch - 
                           trackPoints[i-1].timestamp.millisecondsSinceEpoch) / 1000.0;
          if (timeDiff > 0) {
            final altDiff = _getAltitudeDifference(trackPoints[i], trackPoints[i-1]);
            climbRates.add(altDiff / timeDiff);
          } else {
            climbRates.add(0.0);
          }
        } else {
          climbRates.add(0.0);
        }
        continue;
      }
      
      // Calculate climb rate over the window
      final timeDiffSeconds = (lastInWindow.timestamp.millisecondsSinceEpoch - 
                              firstInWindow.timestamp.millisecondsSinceEpoch) / 1000.0;
      
      if (timeDiffSeconds > 0) {
        final altDiff = _getAltitudeDifference(lastInWindow, firstInWindow);
        climbRates.add(altDiff / timeDiffSeconds);
      } else {
        climbRates.add(0.0);
      }
    }

    return climbRates;
  }
  
  double _getAltitudeDifference(IgcPoint point1, IgcPoint point2) {
    // Use pressure altitude if available (more accurate for vertical speed)
    if (point1.pressureAltitude > 0 && point2.pressureAltitude > 0) {
      return (point1.pressureAltitude - point2.pressureAltitude).toDouble();
    }
    return (point1.gpsAltitude - point2.gpsAltitude).toDouble();
  }

  /// Get climb rate at specific point index
  double getInstantaneousClimbRateAt(int index) {
    final rates = calculateInstantaneousClimbRates();
    if (index >= 0 && index < rates.length) {
      return rates[index];
    }
    return 0.0;
  }

  /// Get 15-second average climb rate at specific point index
  double get15SecondClimbRateAt(int index) {
    final rates = calculate15SecondClimbRates();
    if (index >= 0 && index < rates.length) {
      return rates[index];
    }
    return 0.0;
  }
  
  /// Deprecated: Use get15SecondClimbRateAt instead
  @deprecated
  double get5SecondClimbRateAt(int index) {
    return get15SecondClimbRateAt(index);
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