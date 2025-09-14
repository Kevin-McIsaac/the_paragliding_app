import 'package:latlong2/latlong.dart';

/// Represents an airport from OpenAIP data
class Airport {
  final String id;
  final String name;
  final String? icaoCode;
  final String? iataCode;
  final LatLng position;
  final double? elevation; // meters
  final String? country;
  final String type; // e.g., "large_airport", "medium_airport", "small_airport"
  final List<Runway>? runways;
  final List<Frequency>? frequencies;

  const Airport({
    required this.id,
    required this.name,
    this.icaoCode,
    this.iataCode,
    required this.position,
    this.elevation,
    this.country,
    required this.type,
    this.runways,
    this.frequencies,
  });

  factory Airport.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'];
    final coordinates = geometry['coordinates'] as List;
    final properties = json['properties'] as Map<String, dynamic>;

    return Airport(
      id: json['_id'] as String,
      name: properties['name'] as String,
      icaoCode: properties['icaoCode'] as String?,
      iataCode: properties['iataCode'] as String?,
      position: LatLng(
        coordinates[1] as double, // latitude
        coordinates[0] as double, // longitude
      ),
      elevation: (properties['elevation'] as num?)?.toDouble(),
      country: properties['country'] as String?,
      type: properties['type'] as String? ?? 'airport',
      runways: (properties['runways'] as List?)
          ?.map((r) => Runway.fromJson(r))
          .toList(),
      frequencies: (properties['frequencies'] as List?)
          ?.map((f) => Frequency.fromJson(f))
          .toList(),
    );
  }

  /// Get display name with ICAO code if available
  String get displayName {
    if (icaoCode != null) {
      return '$name ($icaoCode)';
    }
    return name;
  }

  /// Get airport category for icon sizing
  AirportCategory get category {
    switch (type.toLowerCase()) {
      case 'large_airport':
      case 'international_airport':
        return AirportCategory.large;
      case 'medium_airport':
      case 'regional_airport':
        return AirportCategory.medium;
      case 'small_airport':
      case 'local_airport':
      default:
        return AirportCategory.small;
    }
  }
}

/// Airport runway information
class Runway {
  final String? identifier;
  final double? lengthMeters;
  final double? widthMeters;
  final String? surface;

  const Runway({
    this.identifier,
    this.lengthMeters,
    this.widthMeters,
    this.surface,
  });

  factory Runway.fromJson(Map<String, dynamic> json) {
    return Runway(
      identifier: json['identifier'] as String?,
      lengthMeters: (json['length'] as num?)?.toDouble(),
      widthMeters: (json['width'] as num?)?.toDouble(),
      surface: json['surface'] as String?,
    );
  }
}

/// Airport communication frequency
class Frequency {
  final String? type; // e.g., "tower", "ground", "approach"
  final double frequency; // MHz
  final String? description;

  const Frequency({
    this.type,
    required this.frequency,
    this.description,
  });

  factory Frequency.fromJson(Map<String, dynamic> json) {
    return Frequency(
      type: json['type'] as String?,
      frequency: (json['frequency'] as num).toDouble(),
      description: json['description'] as String?,
    );
  }

  /// Format frequency for display (e.g., "118.100")
  String get formattedFrequency {
    return frequency.toStringAsFixed(3);
  }
}

/// Airport size categories for visual representation
enum AirportCategory {
  large,
  medium,
  small,
}