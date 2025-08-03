class Flight {
  final int? id;
  final DateTime date;
  final String launchTime;
  final String landingTime;
  final int duration;
  final int? launchSiteId;
  final int? landingSiteId;
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
  final String source;
  final String? timezone; // Timezone offset (e.g., "+10:00", "-05:30", null for UTC)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Flight({
    this.id,
    required this.date,
    required this.launchTime,
    required this.landingTime,
    required this.duration,
    this.launchSiteId,
    this.landingSiteId,
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
    this.source = 'manual',
    this.timezone,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'launch_time': launchTime,
      'landing_time': landingTime,
      'duration': duration,
      'launch_site_id': launchSiteId,
      'landing_site_id': landingSiteId,
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
      'source': source,
      'timezone': timezone,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
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
      landingSiteId: map['landing_site_id'],
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
      source: map['source'] ?? 'manual',
      timezone: map['timezone'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
    );
  }

  Flight copyWith({
    int? id,
    DateTime? date,
    String? launchTime,
    String? landingTime,
    int? duration,
    int? launchSiteId,
    int? landingSiteId,
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
  }) {
    return Flight(
      id: id ?? this.id,
      date: date ?? this.date,
      launchTime: launchTime ?? this.launchTime,
      landingTime: landingTime ?? this.landingTime,
      duration: duration ?? this.duration,
      launchSiteId: launchSiteId ?? this.launchSiteId,
      landingSiteId: landingSiteId ?? this.landingSiteId,
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
    );
  }
}