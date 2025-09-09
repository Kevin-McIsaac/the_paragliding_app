import 'dart:math';

import '../../services/logging_service.dart';

/// IGC file data model
class IgcFile {
  final DateTime date;
  final String pilot;
  final String gliderType;
  final String gliderID;
  final List<IgcPoint> trackPoints;
  final Map<String, String> headers;
  final String? timezone; // Timezone offset (e.g., "+10:00", "-05:30", null for UTC)
  
  IgcFile({
    required this.date,
    required this.pilot,
    required this.gliderType,
    required this.gliderID,
    required this.trackPoints,
    required this.headers,
    this.timezone,
  });

  /// Create a copy of this IgcFile with trimmed track points
  /// Uses sublist for efficient memory usage (no data duplication)
  IgcFile copyWithTrimmedPoints(int startIndex, int endIndex) {
    if (startIndex < 0 || endIndex >= trackPoints.length || startIndex > endIndex) {
      throw ArgumentError('Invalid indices: startIndex=$startIndex, endIndex=$endIndex, length=${trackPoints.length}');
    }
    
    return IgcFile(
      date: date,
      pilot: pilot,
      gliderType: gliderType,
      gliderID: gliderID,
      trackPoints: trackPoints.sublist(startIndex, endIndex + 1),
      headers: headers,
      timezone: timezone,
    );
  }

  /// Get launch time from first track point
  DateTime get launchTime => trackPoints.isNotEmpty 
      ? trackPoints.first.timestamp 
      : date;

  /// Get landing time from last track point
  DateTime get landingTime => trackPoints.isNotEmpty 
      ? trackPoints.last.timestamp 
      : date;

  /// Calculate flight duration in minutes
  /// If duration is negative, assume flight crossed midnight and add 24 hours
  int get duration {
    final rawDuration = landingTime.difference(launchTime).inMinutes;
    if (rawDuration < 0) {
      // Flight crossed midnight - add 24 hours (1440 minutes)
      return rawDuration + (24 * 60);
    }
    return rawDuration;
  }

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
  @Deprecated('Use calculateGroundTrackDistance() instead')
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
  
  /// Calculate maximum 5-second average climb rates
  Map<String, double> calculate5SecondMaxClimbRates() {
    if (trackPoints.length < 2) {
      return {'maxClimb5Sec': 0, 'maxSink5Sec': 0};
    }

    final fiveSecRates = calculate5SecondClimbRates();
    
    if (fiveSecRates.isEmpty) {
      return {'maxClimb5Sec': 0, 'maxSink5Sec': 0};
    }
    
    double maxClimb5Sec = 0;
    double maxSink5Sec = 0;

    for (final rate in fiveSecRates) {
      if (rate > maxClimb5Sec) maxClimb5Sec = rate;
      if (rate < maxSink5Sec) maxSink5Sec = rate;
    }

    return {
      'maxClimb5Sec': maxClimb5Sec,
      'maxSink5Sec': maxSink5Sec.abs(),
    };
  }
  
  /// Calculate 5-second average climb rates for each point
  List<double> calculate5SecondClimbRates() {
    if (trackPoints.length < 2) return [];

    final climbRates = <double>[];
    
    for (int i = 0; i < trackPoints.length; i++) {
      // Find the point 5 seconds before
      int firstInWindowIndex = i;
      for (int j = i - 1; j >= 0; j--) {
        final timeDiff = trackPoints[i].timestamp.difference(trackPoints[j].timestamp).inSeconds;
        if (timeDiff >= 5) {
          firstInWindowIndex = j;
          break;
        }
      }
      
      // Special cases
      if (i == 0) {
        // First point has no history
        climbRates.add(0.0);
        continue;
      }
      
      if (firstInWindowIndex == i) {
        // Not enough history for 5-second average, use instantaneous
        if (i > 0) {
          final timeDiff = trackPoints[i].timestamp.difference(trackPoints[i-1].timestamp).inSeconds;
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
      
      // Calculate 5-second average
      final firstInWindow = trackPoints[firstInWindowIndex];
      final lastInWindow = trackPoints[i];
      final timeDiffSeconds = lastInWindow.timestamp.difference(firstInWindow.timestamp).inSeconds;
      
      if (timeDiffSeconds > 0) {
        final altDiff = _getAltitudeDifference(lastInWindow, firstInWindow);
        climbRates.add(altDiff / timeDiffSeconds);
      } else {
        climbRates.add(0.0);
      }
    }

    return climbRates;
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
  @Deprecated('Use get15SecondClimbRateAt instead - method name was incorrect')
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

  /// Calculate speed statistics
  Map<String, double> calculateSpeedStatistics() {
    if (trackPoints.length < 2) {
      return {
        'maxGroundSpeed': 0,
        'avgGroundSpeed': 0,
      };
    }

    double maxSpeed = 0;
    double totalSpeed = 0;
    int validSpeedPoints = 0;

    for (int i = 1; i < trackPoints.length; i++) {
      final speed = trackPoints[i].groundSpeed;
      if (speed > 0) {
        if (speed > maxSpeed) maxSpeed = speed;
        totalSpeed += speed;
        validSpeedPoints++;
      }
    }

    return {
      'maxGroundSpeed': maxSpeed,
      'avgGroundSpeed': validSpeedPoints > 0 ? totalSpeed / validSpeedPoints : 0,
    };
  }

  /// Detect and analyze thermals
  Map<String, dynamic> analyzeThermals() {
    if (trackPoints.length < 2) {
      return {
        'thermalCount': 0,
        'avgThermalStrength': 0.0,
        'totalTimeInThermals': 0,
        'bestThermal': 0.0,
      };
    }

    final climbRates = calculate15SecondClimbRates();
    final List<ThermalEvent> thermals = [];
    
    int thermalStart = -1;
    int thermalEnd = -1;
    double thermalClimbSum = 0;
    int thermalPointCount = 0;
    const double thermalThreshold = 0.5; // m/s minimum climb rate
    const int minThermalDuration = 30; // seconds

    for (int i = 0; i < climbRates.length; i++) {
      final climbRate = climbRates[i];
      
      if (climbRate >= thermalThreshold) {
        // In thermal
        if (thermalStart == -1) {
          thermalStart = i;
        }
        thermalEnd = i;
        thermalClimbSum += climbRate;
        thermalPointCount++;
      } else {
        // Out of thermal
        if (thermalStart != -1) {
          // Check if thermal was long enough
          final thermalDuration = trackPoints[thermalEnd].timestamp
              .difference(trackPoints[thermalStart].timestamp)
              .inSeconds;
          
          if (thermalDuration >= minThermalDuration && thermalPointCount > 0) {
            final avgStrength = thermalClimbSum / thermalPointCount;
            thermals.add(ThermalEvent(
              startIndex: thermalStart,
              endIndex: thermalEnd,
              duration: thermalDuration,
              avgStrength: avgStrength,
            ));
          }
          
          // Reset for next thermal
          thermalStart = -1;
          thermalEnd = -1;
          thermalClimbSum = 0;
          thermalPointCount = 0;
        }
      }
    }
    
    // Handle thermal that goes to end of flight
    if (thermalStart != -1) {
      final thermalDuration = trackPoints[thermalEnd].timestamp
          .difference(trackPoints[thermalStart].timestamp)
          .inSeconds;
      
      if (thermalDuration >= minThermalDuration && thermalPointCount > 0) {
        final avgStrength = thermalClimbSum / thermalPointCount;
        thermals.add(ThermalEvent(
          startIndex: thermalStart,
          endIndex: thermalEnd,
          duration: thermalDuration,
          avgStrength: avgStrength,
        ));
      }
    }

    double totalThermalTime = 0;
    double totalThermalStrength = 0;
    double bestThermal = 0;

    for (final thermal in thermals) {
      totalThermalTime += thermal.duration;
      totalThermalStrength += thermal.avgStrength;
      if (thermal.avgStrength > bestThermal) {
        bestThermal = thermal.avgStrength;
      }
    }

    return {
      'thermalCount': thermals.length,
      'avgThermalStrength': thermals.isNotEmpty ? totalThermalStrength / thermals.length : 0.0,
      'totalTimeInThermals': totalThermalTime,
      'bestThermal': bestThermal,
    };
  }

  /// Calculate glide performance statistics
  Map<String, double> calculateGlidePerformance() {
    if (trackPoints.length < 2) {
      return {
        'bestLD': 0,
        'avgLD': 0,
        'longestGlide': 0,
        'climbPercentage': 0,
      };
    }

    final climbRates = calculate15SecondClimbRates();
    final List<double> glideRatios = [];
    double longestGlideDistance = 0;
    double currentGlideDistance = 0;
    int climbingPoints = 0;
    
    for (int i = 1; i < trackPoints.length; i++) {
      final climbRate = i < climbRates.length ? climbRates[i] : 0.0;
      final speed = trackPoints[i].groundSpeed;
      
      if (climbRate > 0.1) { // Climbing
        climbingPoints++;
        // End current glide
        if (currentGlideDistance > longestGlideDistance) {
          longestGlideDistance = currentGlideDistance;
        }
        currentGlideDistance = 0;
      } else if (climbRate < -0.1 && speed > 5) { // Gliding (min 5 km/h to filter out stops)
        // Calculate L/D ratio
        final sinkRate = -climbRate; // Make positive for L/D calculation
        final glideSpeed = speed / 3.6; // Convert km/h to m/s
        final glideRatio = glideSpeed / sinkRate;
        
        if (glideRatio > 0 && glideRatio < 50) { // Reasonable glide ratio range
          glideRatios.add(glideRatio);
        }
        
        // Add to current glide distance
        if (i > 0) {
          currentGlideDistance += _haversineDistance(trackPoints[i-1], trackPoints[i]);
        }
      }
    }
    
    // Check final glide
    if (currentGlideDistance > longestGlideDistance) {
      longestGlideDistance = currentGlideDistance;
    }

    final bestLD = glideRatios.isNotEmpty ? glideRatios.reduce(max) : 0.0;
    final avgLD = glideRatios.isNotEmpty ? glideRatios.reduce((a, b) => a + b) / glideRatios.length : 0.0;
    final climbPercentage = trackPoints.length > 1 ? (climbingPoints / (trackPoints.length - 1)) * 100 : 0.0;

    return {
      'bestLD': bestLD,
      'avgLD': avgLD,
      'longestGlide': longestGlideDistance,
      'climbPercentage': climbPercentage,
    };
  }

  /// Calculate GPS quality metrics
  Map<String, double> calculateGpsQuality() {
    if (trackPoints.isEmpty) {
      return {
        'gpsFixQuality': 0,
        'recordingInterval': 0,
      };
    }

    // Calculate GPS fix quality (percentage of valid fixes)
    final validFixes = trackPoints.where((p) => p.isValid).length;
    final gpsFixQuality = (validFixes / trackPoints.length) * 100;

    // Calculate average recording interval
    double totalInterval = 0;
    int intervalCount = 0;
    
    for (int i = 1; i < trackPoints.length; i++) {
      final interval = trackPoints[i].timestamp
          .difference(trackPoints[i-1].timestamp)
          .inSeconds;
      if (interval > 0 && interval < 300) { // Filter out unreasonable intervals
        totalInterval += interval;
        intervalCount++;
      }
    }
    
    final avgInterval = intervalCount > 0 ? totalInterval / intervalCount : 0.0;

    return {
      'gpsFixQuality': gpsFixQuality,
      'recordingInterval': avgInterval,
    };
  }

  /// Select track points for triangle calculation using time-based sampling
  /// Returns a list of points sampled at the specified interval in seconds
  List<IgcPoint> _selectTimeBasedSamples(int intervalSeconds) {
    if (trackPoints.isEmpty) return [];
    
    List<IgcPoint> samples = [trackPoints.first];
    DateTime nextSampleTime = trackPoints.first.timestamp.add(Duration(seconds: intervalSeconds));
    
    for (final point in trackPoints) {
      if (point.timestamp.isAfter(nextSampleTime) || 
          point.timestamp.isAtSameMomentAs(nextSampleTime)) {
        samples.add(point);
        nextSampleTime = point.timestamp.add(Duration(seconds: intervalSeconds));
      }
    }
    
    // Ensure last point is included if not already
    if (samples.isNotEmpty && samples.last != trackPoints.last) {
      samples.add(trackPoints.last);
    }
    
    return samples;
  }

  /// Calculate triangle using maximum perimeter approach
  /// Returns a map with triangle points and total distance
  /// samplingIntervalSeconds: Time interval in seconds between sample points for triangle optimization
  /// closingDistanceMeters: Distance threshold to validate triangle vertices are meaningful (default 100m)
  Map<String, dynamic> calculateFaiTriangle({required int samplingIntervalSeconds, double closingDistanceMeters = 100.0}) {
    final stopwatch = Stopwatch()..start();
    
    if (trackPoints.length < 3) {
      return {
        'trianglePoints': <IgcPoint>[],
        'triangleDistance': 0.0, // Already in kilometers
      };
    }

    double maxPerimeter = 0.0;
    List<IgcPoint> bestTriangle = [];

    // Use time-based sampling
    final samplePoints = _selectTimeBasedSamples(samplingIntervalSeconds);
    
    int comparisons = 0;
    
    for (int i = 0; i < samplePoints.length; i++) {
      for (int j = i + 1; j < samplePoints.length; j++) {
        for (int k = j + 1; k < samplePoints.length; k++) {
          comparisons++;
          final p1 = samplePoints[i];
          final p2 = samplePoints[j];
          final p3 = samplePoints[k];
          
          // Calculate perimeter using Pythagorean distance
          final distance1 = calculateSimpleDistance(p1, p2);
          final distance2 = calculateSimpleDistance(p2, p3);
          final distance3 = calculateSimpleDistance(p3, p1);
          final perimeter = distance1 + distance2 + distance3;
          
          if (perimeter > maxPerimeter) {
            maxPerimeter = perimeter;
            bestTriangle = [p1, p2, p3];
          }
        }
      }
    }

    stopwatch.stop();

    if (bestTriangle.length != 3) {
      LoggingService.metric('triangle_calc_time', stopwatch.elapsedMilliseconds, 'ms', 'TRIANGLE');
      return {
        'trianglePoints': <IgcPoint>[],
        'triangleDistance': 0.0, // Already in kilometers
      };
    }

    // Validate triangle vertices are outside closing detection threshold
    final launchPoint = trackPoints.first;
    int validVertices = 0;
    final List<double> vertexDistances = [];
    
    for (int i = 0; i < bestTriangle.length; i++) {
      final distance = calculateSimpleDistance(launchPoint, bestTriangle[i]);
      vertexDistances.add(distance);
      if (distance > closingDistanceMeters) {
        validVertices++;
      }
    }
    
    // Check if at least 2 vertices are outside the closing threshold
    if (validVertices < 2) {
      // Triangle is invalid - not enough vertices outside closing distance
      return {
        'trianglePoints': <IgcPoint>[],
        'triangleDistance': 0.0,
      };
    }

    // Calculate final triangle perimeter using Haversine for accuracy
    final distance1 = _haversineDistance(bestTriangle[0], bestTriangle[1]) * 1000; // Convert km to meters
    final distance2 = _haversineDistance(bestTriangle[1], bestTriangle[2]) * 1000;
    final distance3 = _haversineDistance(bestTriangle[2], bestTriangle[0]) * 1000;
    final totalDistance = distance1 + distance2 + distance3;

    // Log structured triangle summary
    LoggingService.summary('TRIANGLE_CALC', {
      'valid': true,
      'distance_km': (totalDistance / 1000).toStringAsFixed(1),
      'vertices_valid': validVertices,
      'time_ms': stopwatch.elapsedMilliseconds,
      'comparisons': comparisons,
      'points_sampled': samplePoints.length,
      'points_total': trackPoints.length,
    });

    return {
      'trianglePoints': bestTriangle,
      'triangleDistance': totalDistance / 1000.0, // Convert meters to kilometers
    };
  }


  /// Find the closing point index by scanning backwards from the end
  /// Returns the index of the first point within maxDistanceMeters of the launch point
  /// Only returns a valid closing point if the track actually left the closing circle
  /// Returns null if no point is found within the specified distance or if the track never left the circle
  int? getClosingPointIndex({double maxDistanceMeters = 100.0}) {
    final stopwatch = Stopwatch()..start();
    
    if (trackPoints.length < 2) {
      LoggingService.debug('Closing point detection: Insufficient points (${trackPoints.length} < 2)');
      return null;
    }
    
    final launchPoint = trackPoints.first;
    int pointsChecked = 0;
    int? potentialClosingIndex;
    
    // Scan backwards from the end of the flight
    for (int i = trackPoints.length - 1; i >= 1; i--) {
      pointsChecked++;
      final currentPoint = trackPoints[i];
      final distance = calculateSimpleDistance(launchPoint, currentPoint);
      
      if (distance <= maxDistanceMeters) {
        potentialClosingIndex = i;
        // Found potential closing point - will validate below
        break; // Found potential closing point, now validate
      }
    }
    
    // If no potential closing point found, flight is definitely open
    if (potentialClosingIndex == null) {
      stopwatch.stop();
      LoggingService.structured('CLOSING_DETECTION', {
        'found': false,
        'reason': 'no_point_in_range',
        'threshold_m': maxDistanceMeters.toStringAsFixed(1),
        'time_ms': stopwatch.elapsedMilliseconds,
        'points_checked': pointsChecked,
      });
      return null;
    }
    
    // Validate that the track actually left the closing circle
    // Scan forward from launch to check if pilot flew away during flight
    bool leftClosingCircle = false;
    int validationPointsChecked = 0;
    
    for (int j = 1; j < potentialClosingIndex; j++) {
      validationPointsChecked++;
      final validationPoint = trackPoints[j];
      final validationDistance = calculateSimpleDistance(launchPoint, validationPoint);
      
      if (validationDistance > maxDistanceMeters) {
        leftClosingCircle = true;
        // Found point outside circle - valid closing
        break;
      }
    }
    
    stopwatch.stop();
    
    if (leftClosingCircle) {
      // Valid closing - track left the circle and returned
      final closingPoint = trackPoints[potentialClosingIndex];
      final closingDistance = calculateSimpleDistance(launchPoint, closingPoint);
      LoggingService.structured('CLOSING_VALIDATION', {
        'valid': true,
        'index': potentialClosingIndex,
        'lat': closingPoint.latitude.toStringAsFixed(6),
        'lon': closingPoint.longitude.toStringAsFixed(6),
        'distance_m': closingDistance.toStringAsFixed(1),
        'threshold_m': maxDistanceMeters.toStringAsFixed(1),
        'time_ms': stopwatch.elapsedMilliseconds,
        'points_checked': pointsChecked + validationPointsChecked,
      });
      return potentialClosingIndex;
    } else {
      // Invalid closing - track never left the closing circle
      LoggingService.structured('CLOSING_DETECTION', {
        'found': false,
        'reason': 'stayed_in_circle',
        'potential_index': potentialClosingIndex,
        'threshold_m': maxDistanceMeters.toStringAsFixed(1),
        'time_ms': stopwatch.elapsedMilliseconds,
        'points_checked': pointsChecked + validationPointsChecked,
      });
      return null; // Not a valid closing - likely ground handling or very short flight
    }
  }

  /// Calculate simple Pythagorean distance in meters (accurate for distances < 1km)
  /// Much faster than haversine calculation for short distances
  double calculateSimpleDistance(IgcPoint p1, IgcPoint p2) {
    const double metersPerDegreeLat = 111320.0; // Meters per degree latitude (constant)
    final double metersPerDegreeLon = 111320.0 * cos(p1.latitude * pi / 180); // Adjust for longitude at this latitude
    
    final double deltaLat = (p2.latitude - p1.latitude) * metersPerDegreeLat;
    final double deltaLon = (p2.longitude - p1.longitude) * metersPerDegreeLon;
    
    return sqrt(deltaLat * deltaLat + deltaLon * deltaLon);
  }
}

/// Represents a thermal event detected in the flight
class ThermalEvent {
  final int startIndex;
  final int endIndex;
  final int duration; // seconds
  final double avgStrength; // m/s
  
  ThermalEvent({
    required this.startIndex,
    required this.endIndex,
    required this.duration,
    required this.avgStrength,
  });
}

/// Single track point in IGC file
class IgcPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final int pressureAltitude;
  final int gpsAltitude;
  final bool isValid;
  
  // Optional references for calculating virtual properties
  final IgcFile? parentFile;
  final int? pointIndex;
  
  IgcPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.pressureAltitude,
    required this.gpsAltitude,
    required this.isValid,
    this.parentFile,
    this.pointIndex,
  });
  
  /// Virtual getter for instantaneous climb rate in m/s
  /// Calculated from the previous point using GPS altitude or pressure altitude if available
  double get climbRate {
    if (parentFile == null || pointIndex == null || pointIndex! == 0) {
      return 0.0;
    }
    
    if (pointIndex! >= parentFile!.trackPoints.length) {
      return 0.0;
    }
    
    final prevPoint = parentFile!.trackPoints[pointIndex! - 1];
    final timeDiff = timestamp.difference(prevPoint.timestamp).inSeconds;
    
    if (timeDiff <= 0) return 0.0;
    
    // Use pressure altitude if available (more accurate for vertical speed)
    final altDiff = (pressureAltitude > 0 && prevPoint.pressureAltitude > 0)
        ? (pressureAltitude - prevPoint.pressureAltitude).toDouble()
        : (gpsAltitude - prevPoint.gpsAltitude).toDouble();
    
    return altDiff / timeDiff; // m/s
  }
  
  /// Virtual getter for ground speed in km/h
  /// Calculated from the previous point using haversine distance formula
  double get groundSpeed {
    if (parentFile == null || pointIndex == null || pointIndex! == 0) {
      return 0.0;
    }
    
    if (pointIndex! >= parentFile!.trackPoints.length) {
      return 0.0;
    }
    
    final prevPoint = parentFile!.trackPoints[pointIndex! - 1];
    final distance = _calculateDistanceMeters(prevPoint, this); // meters
    final timeDiff = timestamp.difference(prevPoint.timestamp).inSeconds;
    
    if (timeDiff <= 0) return 0.0;
    
    return (distance / timeDiff) * 3.6; // Convert m/s to km/h
  }
  
  /// Virtual getter for 5-second trailing average climb rate in m/s
  /// Calculates average climb rate over the past 5 seconds from current point
  double get climbRate5s {
    if (parentFile == null || pointIndex == null) {
      return 0.0;
    }
    
    final tracks = parentFile!.trackPoints;
    if (pointIndex! >= tracks.length || pointIndex! == 0) {
      return climbRate; // Fallback to instantaneous for first point
    }
    
    // Find the first point in the 5-second window
    IgcPoint? firstInWindow;
    for (int i = pointIndex! - 1; i >= 0; i--) {
      final timeDiff = timestamp.difference(tracks[i].timestamp).inSeconds;
      if (timeDiff >= 5) {
        firstInWindow = tracks[i];
        break;
      }
    }
    
    // If we don't have enough points in the window, use instantaneous rate
    if (firstInWindow == null || firstInWindow == this) {
      return climbRate;
    }
    
    // Calculate the average climb rate over the window
    final timeDiffSeconds = timestamp.difference(firstInWindow.timestamp).inSeconds.toDouble();
    
    if (timeDiffSeconds <= 0) {
      return climbRate; // Fallback to instantaneous
    }
    
    // Use pressure altitude if available (more accurate for vertical speed)
    final altDiff = (pressureAltitude > 0 && firstInWindow.pressureAltitude > 0)
        ? (pressureAltitude - firstInWindow.pressureAltitude).toDouble()
        : (gpsAltitude - firstInWindow.gpsAltitude).toDouble();
    
    return altDiff / timeDiffSeconds; // m/s
  }
  
  /// Virtual getter for 15-second trailing average climb rate in m/s
  /// Calculates average climb rate over the past 15 seconds from current point
  double get climbRate15s {
    if (parentFile == null || pointIndex == null) {
      return 0.0;
    }
    
    final tracks = parentFile!.trackPoints;
    if (pointIndex! >= tracks.length || pointIndex! == 0) {
      return climbRate; // Fallback to instantaneous for first point
    }
    
    // Find the first point in the 15-second window
    IgcPoint? firstInWindow;
    for (int i = pointIndex! - 1; i >= 0; i--) {
      final timeDiff = timestamp.difference(tracks[i].timestamp).inSeconds;
      if (timeDiff >= 15) {
        firstInWindow = tracks[i];
        break;
      }
    }
    
    // If we don't have enough points in the window, use instantaneous rate
    if (firstInWindow == null || firstInWindow == this) {
      return climbRate;
    }
    
    // Calculate the average climb rate over the window
    final timeDiffSeconds = timestamp.difference(firstInWindow.timestamp).inSeconds.toDouble();
    
    if (timeDiffSeconds <= 0) {
      return climbRate; // Fallback to instantaneous
    }
    
    // Use pressure altitude if available (more accurate for vertical speed)
    final altDiff = (pressureAltitude > 0 && firstInWindow.pressureAltitude > 0)
        ? (pressureAltitude - firstInWindow.pressureAltitude).toDouble()
        : (gpsAltitude - firstInWindow.gpsAltitude).toDouble();
    
    return altDiff / timeDiffSeconds; // m/s
  }
  
  /// Calculate distance between two points in meters using Haversine formula
  double _calculateDistanceMeters(IgcPoint p1, IgcPoint p2) {
    const double earthRadius = 6371000; // meters
    
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

}