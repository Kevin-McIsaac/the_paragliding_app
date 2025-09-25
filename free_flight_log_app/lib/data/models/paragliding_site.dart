import 'dart:math';
import 'package:flutter/material.dart';

class ParaglidingSite {
  final int? id;
  final String name;
  final double latitude;
  final double longitude;
  final int? altitude;
  final String? description;
  final List<String> windDirections;
  final String siteType; // 'launch', 'landing', 'both'
  final int? rating; // 1-5 stars if available from API
  final String? country;
  final String? region;
  final double? popularity; // Calculated popularity score
  final int flightCount; // Number of flights from local database

  const ParaglidingSite({
    this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.description,
    this.windDirections = const [],
    required this.siteType,
    this.rating,
    this.country,
    this.region,
    this.popularity,
    this.flightCount = 0,
  });

  // Computed properties
  bool get hasFlights => flightCount > 0;

  // Helper to get marker color - moved from UnifiedSite
  Color get markerColor {
    return hasFlights
        ? Colors.blue  // Blue for flown sites (sites with flights)
        : Colors.deepPurple; // Deep purple for new sites (from PGE API)
  }

  /// Create from JSON (for loading from assets)
  factory ParaglidingSite.fromJson(Map<String, dynamic> json) {
    return ParaglidingSite(
      id: json['id'] as int?,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      altitude: json['altitude'] as int?,
      description: json['description'] as String?,
      windDirections: json['wind_directions'] != null
          ? List<String>.from(json['wind_directions'] as List)
          : [],
      siteType: json['site_type'] as String? ?? 'launch',
      rating: json['rating'] as int?,
      country: json['country'] as String?,
      region: json['region'] as String?,
      popularity: json['popularity'] != null
          ? (json['popularity'] as num).toDouble()
          : null,
    );
  }

  /// Convert to JSON (for saving/exporting)
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (description != null) 'description': description,
      if (windDirections.isNotEmpty) 'wind_directions': windDirections,
      'site_type': siteType,
      if (rating != null) 'rating': rating,
      if (country != null) 'country': country,
      if (region != null) 'region': region,
      if (popularity != null) 'popularity': popularity,
    };
  }

  /// Create from database row
  factory ParaglidingSite.fromMap(Map<String, dynamic> map) {
    return ParaglidingSite(
      id: map['id'] as int?,
      name: map['name'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      altitude: map['altitude'] as int?,
      description: map['description'] as String?,
      windDirections: map['wind_directions'] != null
          ? List<String>.from(map['wind_directions'].split(','))
          : [],
      siteType: map['site_type'] as String? ?? 'launch',
      rating: map['rating'] as int?,
      country: map['country'] as String?,
      region: map['region'] as String?,
      popularity: map['popularity'] != null
          ? (map['popularity'] as num).toDouble()
          : null,
    );
  }

  /// Convert to database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (description != null) 'description': description,
      'wind_directions': windDirections.join(','),
      'site_type': siteType,
      'rating': rating,
      if (country != null) 'country': country,
      if (region != null) 'region': region,
      if (popularity != null) 'popularity': popularity,
    };
  }

  /// Calculate distance from this site to given coordinates in meters
  double distanceTo(double lat, double lon) {
    const double earthRadius = 6371000; // meters
    final double dLat = _toRadians(lat - latitude);
    final double dLon = _toRadians(lon - longitude);
    
    final double a = 
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(latitude)) * cos(_toRadians(lat)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * pi / 180;

  /// Check if this site is suitable for given wind direction
  bool isSuitableForWind(String windDirection) {
    if (windDirections.isEmpty) return true; // No restrictions
    return windDirections.contains(windDirection.toUpperCase());
  }

  /// Format site name with type prefix if needed
  String get displayName {
    switch (siteType) {
      case 'launch':
        return name;
      case 'landing':
        return 'LZ: $name';
      case 'both':
        return name;
      default:
        return name;
    }
  }

  /// Get formatted location string
  String get locationString {
    final parts = <String>[];
    if (region != null && region!.isNotEmpty) parts.add(region!);
    if (country != null && country!.isNotEmpty) parts.add(country!);
    return parts.join(', ');
  }

  @override
  String toString() {
    return 'ParaglidingSite(name: $name, lat: ${latitude.toStringAsFixed(4)}, '
           'lon: ${longitude.toStringAsFixed(4)}, type: $siteType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ParaglidingSite &&
        other.name == name &&
        (other.latitude - latitude).abs() < 0.0001 &&
        (other.longitude - longitude).abs() < 0.0001;
  }

  @override
  int get hashCode => Object.hash(name, latitude, longitude);

  /// Create a copy with updated fields
  ParaglidingSite copyWith({
    int? id,
    String? name,
    double? latitude,
    double? longitude,
    int? altitude,
    String? description,
    List<String>? windDirections,
    String? siteType,
    int? rating,
    String? country,
    String? region,
    double? popularity,
    int? flightCount,
  }) {
    return ParaglidingSite(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      description: description ?? this.description,
      windDirections: windDirections ?? this.windDirections,
      siteType: siteType ?? this.siteType,
      rating: rating ?? this.rating,
      country: country ?? this.country,
      region: region ?? this.region,
      popularity: popularity ?? this.popularity,
      flightCount: flightCount ?? this.flightCount,
    );
  }
}

