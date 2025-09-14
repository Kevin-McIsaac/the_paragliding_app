import 'package:latlong2/latlong.dart';

/// Represents a navigation aid from OpenAIP data
class Navaid {
  final String id;
  final String name;
  final String? identifier; // e.g., "SFO", "LAX"
  final LatLng position;
  final NavaidType type;
  final double? frequency; // kHz for NDB, MHz for VOR/DME
  final double? elevation; // meters
  final String? country;
  final int? range; // nautical miles

  const Navaid({
    required this.id,
    required this.name,
    this.identifier,
    required this.position,
    required this.type,
    this.frequency,
    this.elevation,
    this.country,
    this.range,
  });

  factory Navaid.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'];
    final coordinates = geometry['coordinates'] as List;
    final properties = json['properties'] as Map<String, dynamic>;

    return Navaid(
      id: json['_id'] as String,
      name: properties['name'] as String,
      identifier: properties['identifier'] as String?,
      position: LatLng(
        coordinates[1] as double, // latitude
        coordinates[0] as double, // longitude
      ),
      type: NavaidType.fromString(properties['type'] as String? ?? 'unknown'),
      frequency: (properties['frequency'] as num?)?.toDouble(),
      elevation: (properties['elevation'] as num?)?.toDouble(),
      country: properties['country'] as String?,
      range: (properties['range'] as num?)?.toInt(),
    );
  }

  /// Get display name with identifier if available
  String get displayName {
    if (identifier != null) {
      return '$name ($identifier)';
    }
    return name;
  }

  /// Format frequency for display based on type
  String? get formattedFrequency {
    if (frequency == null) return null;

    switch (type) {
      case NavaidType.vor:
      case NavaidType.vordme:
      case NavaidType.dme:
        return '${frequency!.toStringAsFixed(2)} MHz';
      case NavaidType.ndb:
        return '${frequency!.toStringAsFixed(0)} kHz';
      case NavaidType.tacan:
        return 'CH ${frequency!.toStringAsFixed(0)}';
      default:
        return frequency!.toStringAsFixed(2);
    }
  }
}

/// Types of navigation aids
enum NavaidType {
  vor('VOR', 'VHF Omnidirectional Range'),
  vordme('VOR/DME', 'VOR with Distance Measuring Equipment'),
  dme('DME', 'Distance Measuring Equipment'),
  ndb('NDB', 'Non-Directional Beacon'),
  tacan('TACAN', 'Tactical Air Navigation'),
  waypoint('Waypoint', 'GPS Waypoint'),
  unknown('Unknown', 'Unknown Navigation Aid');

  const NavaidType(this.code, this.description);

  final String code;
  final String description;

  /// Create NavaidType from string
  static NavaidType fromString(String value) {
    final normalized = value.toUpperCase().replaceAll('/', '').replaceAll('-', '');

    switch (normalized) {
      case 'VOR':
        return NavaidType.vor;
      case 'VORDME':
      case 'VOR_DME':
        return NavaidType.vordme;
      case 'DME':
        return NavaidType.dme;
      case 'NDB':
        return NavaidType.ndb;
      case 'TACAN':
        return NavaidType.tacan;
      case 'WAYPOINT':
      case 'GPS':
        return NavaidType.waypoint;
      default:
        return NavaidType.unknown;
    }
  }

  /// Get icon character for map display
  String get iconSymbol {
    switch (this) {
      case NavaidType.vor:
      case NavaidType.vordme:
        return '⬡'; // Hexagon for VOR
      case NavaidType.dme:
        return '◇'; // Diamond for DME
      case NavaidType.ndb:
        return '●'; // Filled circle for NDB
      case NavaidType.tacan:
        return '⬢'; // Hexagon outline for TACAN
      case NavaidType.waypoint:
        return '◉'; // Circle with dot for waypoints
      case NavaidType.unknown:
        return '?';
    }
  }
}