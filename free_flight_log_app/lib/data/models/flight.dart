import 'dart:convert';
import '../../services/logging_service.dart';

class Flight {
  // Constants
  static const int expectedTrianglePoints = 3;
  final int? id;
  final DateTime date;
  final String launchTime;
  final String landingTime;
  final int duration;
  final int? launchSiteId;
  final String? launchSiteName;  // From JOIN with sites table
  final double? launchLatitude;
  final double? launchLongitude;
  final double? launchAltitude;
  final double? landingLatitude;
  final double? landingLongitude;
  final double? landingAltitude;
  final String? landingDescription;
  final double? maxAltitude;
  final double? maxClimbRate;
  final double? maxSinkRate;
  final double? maxClimbRate5Sec;
  final double? maxSinkRate5Sec;
  final double? distance;
  final double? straightDistance;
  final double? faiTriangleDistance;
  final String? faiTrianglePoints; // JSON string storing triangle points
  final int? wingId;
  final String? notes;
  final String? trackLogPath;
  final String? originalFilename; // Original IGC filename for traceability
  final String source;
  final String? timezone; // Timezone offset (e.g., "+10:00", "-05:30", null for UTC)
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // New IGC statistics
  final double? maxGroundSpeed; // km/h
  final double? avgGroundSpeed; // km/h
  final int? thermalCount;
  final double? avgThermalStrength; // m/s
  final int? totalTimeInThermals; // seconds
  final double? bestThermal; // m/s
  final double? bestLD; // glide ratio
  final double? avgLD; // glide ratio
  final double? longestGlide; // km
  final double? climbPercentage; // percentage
  final double? gpsFixQuality; // percentage
  final double? recordingInterval; // seconds
  
  // Takeoff/Landing Detection fields
  final int? takeoffIndex; // Index of detected takeoff point in IGC track points
  final int? landingIndex; // Index of detected landing point in IGC track points
  final DateTime? detectedTakeoffTime; // Detected takeoff time (may differ from launchTime)
  final DateTime? detectedLandingTime; // Detected landing time (may differ from landingTime)

  Flight({
    this.id,
    required this.date,
    required this.launchTime,
    required this.landingTime,
    required this.duration,
    this.launchSiteId,
    this.launchSiteName,
    this.launchLatitude,
    this.launchLongitude,
    this.launchAltitude,
    this.landingLatitude,
    this.landingLongitude,
    this.landingAltitude,
    this.landingDescription,
    this.maxAltitude,
    this.maxClimbRate,
    this.maxSinkRate,
    this.maxClimbRate5Sec,
    this.maxSinkRate5Sec,
    this.distance,
    this.straightDistance,
    this.faiTriangleDistance,
    this.faiTrianglePoints,
    this.wingId,
    this.notes,
    this.trackLogPath,
    this.originalFilename,
    this.source = 'manual',
    this.timezone,
    this.createdAt,
    this.updatedAt,
    this.maxGroundSpeed,
    this.avgGroundSpeed,
    this.thermalCount,
    this.avgThermalStrength,
    this.totalTimeInThermals,
    this.bestThermal,
    this.bestLD,
    this.avgLD,
    this.longestGlide,
    this.climbPercentage,
    this.gpsFixQuality,
    this.recordingInterval,
    this.takeoffIndex,
    this.landingIndex,
    this.detectedTakeoffTime,
    this.detectedLandingTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'launch_time': launchTime,
      'landing_time': landingTime,
      'duration': duration,
      'launch_site_id': launchSiteId,
      'launch_latitude': launchLatitude,
      'launch_longitude': launchLongitude,
      'launch_altitude': launchAltitude,
      'landing_latitude': landingLatitude,
      'landing_longitude': landingLongitude,
      'landing_altitude': landingAltitude,
      'landing_description': landingDescription,
      // Note: launchSiteName is not stored in flights table (from JOIN)
      'max_altitude': maxAltitude,
      'max_climb_rate': maxClimbRate,
      'max_sink_rate': maxSinkRate,
      'max_climb_rate_5_sec': maxClimbRate5Sec,
      'max_sink_rate_5_sec': maxSinkRate5Sec,
      'distance': distance,
      'straight_distance': straightDistance,
      'fai_triangle_distance': faiTriangleDistance,
      'fai_triangle_points': faiTrianglePoints,
      'wing_id': wingId,
      'notes': notes,
      'track_log_path': trackLogPath,
      'original_filename': originalFilename,
      'source': source,
      'timezone': timezone,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'max_ground_speed': maxGroundSpeed,
      'avg_ground_speed': avgGroundSpeed,
      'thermal_count': thermalCount,
      'avg_thermal_strength': avgThermalStrength,
      'total_time_in_thermals': totalTimeInThermals,
      'best_thermal': bestThermal,
      'best_ld': bestLD,
      'avg_ld': avgLD,
      'longest_glide': longestGlide,
      'climb_percentage': climbPercentage,
      'gps_fix_quality': gpsFixQuality,
      'recording_interval': recordingInterval,
      'takeoff_index': takeoffIndex,
      'landing_index': landingIndex,
      'detected_takeoff_time': detectedTakeoffTime?.toIso8601String(),
      'detected_landing_time': detectedLandingTime?.toIso8601String(),
    };
  }

  factory Flight.fromMap(Map<String, dynamic> map) {
    return Flight(
      id: map['id'],
      date: DateTime.parse(map['date']),
      launchTime: map['launch_time'],
      landingTime: map['landing_time'],
      duration: map['duration'],
      launchSiteId: map['launch_site_id'],
      launchSiteName: map['launch_site_name'], // From JOIN query
      launchLatitude: map['launch_latitude']?.toDouble(),
      launchLongitude: map['launch_longitude']?.toDouble(),
      launchAltitude: map['launch_altitude']?.toDouble(),
      landingLatitude: map['landing_latitude']?.toDouble(),
      landingLongitude: map['landing_longitude']?.toDouble(),
      landingAltitude: map['landing_altitude']?.toDouble(),
      landingDescription: map['landing_description'],
      maxAltitude: map['max_altitude']?.toDouble(),
      maxClimbRate: map['max_climb_rate']?.toDouble(),
      maxSinkRate: map['max_sink_rate']?.toDouble(),
      maxClimbRate5Sec: map['max_climb_rate_5_sec']?.toDouble(),
      maxSinkRate5Sec: map['max_sink_rate_5_sec']?.toDouble(),
      distance: map['distance']?.toDouble(),
      straightDistance: map['straight_distance']?.toDouble(),
      faiTriangleDistance: map['fai_triangle_distance']?.toDouble(),
      faiTrianglePoints: map['fai_triangle_points'],
      wingId: map['wing_id'],
      notes: map['notes'],
      trackLogPath: map['track_log_path'],
      originalFilename: map['original_filename'],
      source: map['source'] ?? 'manual',
      timezone: map['timezone'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
      maxGroundSpeed: map['max_ground_speed']?.toDouble(),
      avgGroundSpeed: map['avg_ground_speed']?.toDouble(),
      thermalCount: map['thermal_count']?.toInt(),
      avgThermalStrength: map['avg_thermal_strength']?.toDouble(),
      totalTimeInThermals: map['total_time_in_thermals']?.toInt(),
      bestThermal: map['best_thermal']?.toDouble(),
      bestLD: map['best_ld']?.toDouble(),
      avgLD: map['avg_ld']?.toDouble(),
      longestGlide: map['longest_glide']?.toDouble(),
      climbPercentage: map['climb_percentage']?.toDouble(),
      gpsFixQuality: map['gps_fix_quality']?.toDouble(),
      recordingInterval: map['recording_interval']?.toDouble(),
      takeoffIndex: map['takeoff_index']?.toInt(),
      landingIndex: map['landing_index']?.toInt(),
      detectedTakeoffTime: map['detected_takeoff_time'] != null ? DateTime.parse(map['detected_takeoff_time']) : null,
      detectedLandingTime: map['detected_landing_time'] != null ? DateTime.parse(map['detected_landing_time']) : null,
    );
  }

  Flight copyWith({
    int? id,
    DateTime? date,
    String? launchTime,
    String? landingTime,
    int? duration,
    int? launchSiteId,
    String? launchSiteName,
    double? launchLatitude,
    double? launchLongitude,
    double? launchAltitude,
    double? landingLatitude,
    double? landingLongitude,
    double? landingAltitude,
    String? landingDescription,
    double? maxAltitude,
    double? maxClimbRate,
    double? maxSinkRate,
    double? maxClimbRate5Sec,
    double? maxSinkRate5Sec,
    double? distance,
    double? straightDistance,
    double? faiTriangleDistance,
    String? faiTrianglePoints,
    int? wingId,
    String? notes,
    String? trackLogPath,
    String? source,
    String? timezone,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? maxGroundSpeed,
    double? avgGroundSpeed,
    int? thermalCount,
    double? avgThermalStrength,
    int? totalTimeInThermals,
    double? bestThermal,
    double? bestLD,
    double? avgLD,
    double? longestGlide,
    double? climbPercentage,
    double? gpsFixQuality,
    double? recordingInterval,
    int? takeoffIndex,
    int? landingIndex,
    DateTime? detectedTakeoffTime,
    DateTime? detectedLandingTime,
  }) {
    return Flight(
      id: id ?? this.id,
      date: date ?? this.date,
      launchTime: launchTime ?? this.launchTime,
      landingTime: landingTime ?? this.landingTime,
      duration: duration ?? this.duration,
      launchSiteId: launchSiteId ?? this.launchSiteId,
      launchSiteName: launchSiteName ?? this.launchSiteName,
      launchLatitude: launchLatitude ?? this.launchLatitude,
      launchLongitude: launchLongitude ?? this.launchLongitude,
      launchAltitude: launchAltitude ?? this.launchAltitude,
      landingLatitude: landingLatitude ?? this.landingLatitude,
      landingLongitude: landingLongitude ?? this.landingLongitude,
      landingAltitude: landingAltitude ?? this.landingAltitude,
      landingDescription: landingDescription ?? this.landingDescription,
      maxAltitude: maxAltitude ?? this.maxAltitude,
      maxClimbRate: maxClimbRate ?? this.maxClimbRate,
      maxSinkRate: maxSinkRate ?? this.maxSinkRate,
      maxClimbRate5Sec: maxClimbRate5Sec ?? this.maxClimbRate5Sec,
      maxSinkRate5Sec: maxSinkRate5Sec ?? this.maxSinkRate5Sec,
      distance: distance ?? this.distance,
      straightDistance: straightDistance ?? this.straightDistance,
      faiTriangleDistance: faiTriangleDistance ?? this.faiTriangleDistance,
      faiTrianglePoints: faiTrianglePoints ?? this.faiTrianglePoints,
      wingId: wingId ?? this.wingId,
      notes: notes ?? this.notes,
      trackLogPath: trackLogPath ?? this.trackLogPath,
      source: source ?? this.source,
      timezone: timezone ?? this.timezone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      maxGroundSpeed: maxGroundSpeed ?? this.maxGroundSpeed,
      avgGroundSpeed: avgGroundSpeed ?? this.avgGroundSpeed,
      thermalCount: thermalCount ?? this.thermalCount,
      avgThermalStrength: avgThermalStrength ?? this.avgThermalStrength,
      totalTimeInThermals: totalTimeInThermals ?? this.totalTimeInThermals,
      bestThermal: bestThermal ?? this.bestThermal,
      bestLD: bestLD ?? this.bestLD,
      avgLD: avgLD ?? this.avgLD,
      longestGlide: longestGlide ?? this.longestGlide,
      climbPercentage: climbPercentage ?? this.climbPercentage,
      gpsFixQuality: gpsFixQuality ?? this.gpsFixQuality,
      recordingInterval: recordingInterval ?? this.recordingInterval,
      takeoffIndex: takeoffIndex ?? this.takeoffIndex,
      landingIndex: landingIndex ?? this.landingIndex,
      detectedTakeoffTime: detectedTakeoffTime ?? this.detectedTakeoffTime,
      detectedLandingTime: detectedLandingTime ?? this.detectedLandingTime,
    );
  }
  
  /// Parse the JSON-stored FAI triangle points into a list of coordinate maps
  /// Returns null if no triangle points are stored or if parsing fails
  List<Map<String, double>>? getParsedTrianglePoints() {
    if (faiTrianglePoints == null || faiTrianglePoints!.isEmpty) {
      return null;
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(faiTrianglePoints!);
      
      // Validate JSON structure
      if (!_isValidTrianglePointsStructure(decoded)) {
        LoggingService.warning('Flight.getParsedTrianglePoints: Invalid triangle points structure for flight $id');
        return null;
      }
      
      final points = decoded.cast<Map<String, dynamic>>().map((point) {
        return {
          'lat': (point['lat'] as num).toDouble(),
          'lng': (point['lng'] as num).toDouble(),
          'alt': (point['alt'] as num).toDouble(),
        };
      }).toList();
      
      // Validate that we have exactly 3 distinct points
      if (!_isValidTriangle(points)) {
        LoggingService.warning('Flight.getParsedTrianglePoints: Invalid triangle geometry for flight $id');
        return null;
      }
      
      return points;
    } catch (e) {
      LoggingService.warning('Flight.getParsedTrianglePoints: Failed to parse triangle points JSON for flight $id', e);
      return null;
    }
  }

  /// Validates that the decoded JSON structure is correct for triangle points
  bool _isValidTrianglePointsStructure(List<dynamic> points) {
    if (points.length != expectedTrianglePoints) {
      return false;
    }
    
    for (final point in points) {
      if (point is! Map<String, dynamic>) {
        return false;
      }
      
      // Check required fields exist and are numeric
      if (!point.containsKey('lat') || !point.containsKey('lng') || !point.containsKey('alt')) {
        return false;
      }
      
      if (point['lat'] is! num || point['lng'] is! num || point['alt'] is! num) {
        return false;
      }
      
      // Basic coordinate validation
      final lat = point['lat'] as num;
      final lng = point['lng'] as num;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        return false;
      }
    }
    
    return true;
  }

  /// Validates that the three points form a valid triangle (distinct points)
  bool _isValidTriangle(List<Map<String, double>> points) {
    if (points.length != expectedTrianglePoints) {
      return false;
    }
    
    // Check that all points are distinct (no two points are the same)
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        final p1 = points[i];
        final p2 = points[j];
        
        // Consider points the same if they're within ~1 meter (very small lat/lng difference)
        const double tolerance = 0.00001; // approximately 1 meter
        if ((p1['lat']! - p2['lat']!).abs() < tolerance && 
            (p1['lng']! - p2['lng']!).abs() < tolerance) {
          return false;
        }
      }
    }
    
    return true;
  }

  /// Helper method to encode triangle points to JSON
  static String? encodeTrianglePointsToJson(List<dynamic> trianglePoints) {
    if (trianglePoints.length != expectedTrianglePoints) {
      return null;
    }
    
    try {
      return jsonEncode(
        trianglePoints.map((point) => {
          'lat': point.latitude,
          'lng': point.longitude,
          'alt': point.gpsAltitude,
        }).toList()
      );
    } catch (e) {
      LoggingService.error('Flight.encodeTrianglePointsToJson: Failed to encode triangle points', e);
      return null;
    }
  }
  
  /// Get effective takeoff time (detected time if available, otherwise launch time)
  String get effectiveTakeoffTime {
    if (detectedTakeoffTime != null) {
      return '${detectedTakeoffTime!.hour.toString().padLeft(2, '0')}:${detectedTakeoffTime!.minute.toString().padLeft(2, '0')}';
    }
    return launchTime;
  }
  
  /// Get effective landing time (detected time if available, otherwise landing time)  
  String get effectiveLandingTime {
    if (detectedLandingTime != null) {
      return '${detectedLandingTime!.hour.toString().padLeft(2, '0')}:${detectedLandingTime!.minute.toString().padLeft(2, '0')}';
    }
    return landingTime;
  }
  
  /// Get effective flight duration in minutes (detected duration if available, otherwise stored duration)
  int get effectiveDuration {
    if (detectedTakeoffTime != null && detectedLandingTime != null) {
      return detectedLandingTime!.difference(detectedTakeoffTime!).inMinutes;
    }
    return duration;
  }
  
  /// Check if this flight has takeoff/landing detection data
  bool get hasDetectionData => takeoffIndex != null && landingIndex != null;
  
  /// Get trimmed track points based on detected takeoff/landing indices
  /// Returns null if no detection data available - caller should use full track points
  ({int startIndex, int endIndex})? get trimmedIndices {
    if (!hasDetectionData) return null;
    return (startIndex: takeoffIndex!, endIndex: landingIndex!);
  }
}