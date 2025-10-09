class Site {
  final int? id;
  final String name;
  final double latitude;
  final double longitude;
  final double? altitude;
  final String? country;
  final bool customName;
  final int? pgeSiteId;  // Foreign key to pge_sites table
  final DateTime? createdAt;
  final int? flightCount;

  Site({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.country,
    this.customName = false,
    this.pgeSiteId,
    this.createdAt,
    this.flightCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'country': country,
      'custom_name': customName ? 1 : 0,
      'pge_site_id': pgeSiteId,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  factory Site.fromMap(Map<String, dynamic> map) {
    return Site(
      id: map['id'],
      name: map['name'],
      latitude: map['latitude']?.toDouble(),
      longitude: map['longitude']?.toDouble(),
      altitude: map['altitude']?.toDouble(),
      country: map['country'],
      customName: map['custom_name'] == 1,
      pgeSiteId: map['pge_site_id'],
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : null,
      flightCount: map['flight_count'],
    );
  }

  Site copyWith({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    double? altitude,
    String? country,
    bool? customName,
    int? pgeSiteId,
    DateTime? createdAt,
    int? flightCount,
  }) {
    return Site(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      country: country ?? this.country,
      customName: customName ?? this.customName,
      pgeSiteId: pgeSiteId ?? this.pgeSiteId,
      createdAt: createdAt ?? this.createdAt,
      flightCount: flightCount ?? this.flightCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Site && other.id == id && id != null;
  }

  @override
  int get hashCode => id.hashCode;
}