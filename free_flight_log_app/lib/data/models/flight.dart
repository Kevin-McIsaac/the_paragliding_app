class Flight {
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
    );
  }
}