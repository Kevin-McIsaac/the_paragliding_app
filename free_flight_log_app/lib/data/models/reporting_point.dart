import 'package:latlong2/latlong.dart';

/// Represents a VFR reporting point from OpenAIP data
class ReportingPoint {
  final String id;
  final String name;
  final String? identifier; // Short code/identifier
  final LatLng position;
  final ReportingPointType type;
  final double? elevation; // meters
  final String? country;
  final String? description;
  final AltitudeRestriction? altitudeRestriction;

  const ReportingPoint({
    required this.id,
    required this.name,
    this.identifier,
    required this.position,
    required this.type,
    this.elevation,
    this.country,
    this.description,
    this.altitudeRestriction,
  });

  factory ReportingPoint.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'];
    final coordinates = geometry['coordinates'] as List;
    final properties = json['properties'] as Map<String, dynamic>;

    return ReportingPoint(
      id: json['_id'] as String,
      name: properties['name'] as String,
      identifier: properties['identifier'] as String?,
      position: LatLng(
        coordinates[1] as double, // latitude
        coordinates[0] as double, // longitude
      ),
      type: ReportingPointType.fromString(
        properties['type'] as String? ?? 'visual',
      ),
      elevation: (properties['elevation'] as num?)?.toDouble(),
      country: properties['country'] as String?,
      description: properties['description'] as String?,
      altitudeRestriction: properties['altitudeRestriction'] != null
          ? AltitudeRestriction.fromJson(properties['altitudeRestriction'])
          : null,
    );
  }

  /// Get display name with identifier if available
  String get displayName {
    if (identifier != null) {
      return '$name ($identifier)';
    }
    return name;
  }

  /// Get tooltip text with altitude restrictions if any
  String get tooltipText {
    final buffer = StringBuffer(displayName);

    if (description != null && description!.isNotEmpty) {
      buffer.write('\n${description!}');
    }

    if (altitudeRestriction != null) {
      buffer.write('\n${altitudeRestriction!.description}');
    }

    if (elevation != null) {
      buffer.write('\nElevation: ${elevation!.toInt()}m');
    }

    return buffer.toString();
  }
}

/// Types of reporting points
enum ReportingPointType {
  visual('Visual', 'Visual Reporting Point'),
  compulsory('Compulsory', 'Compulsory Reporting Point'),
  enroute('En-route', 'En-route Reporting Point'),
  terminal('Terminal', 'Terminal Area Reporting Point');

  const ReportingPointType(this.code, this.description);

  final String code;
  final String description;

  /// Create ReportingPointType from string
  static ReportingPointType fromString(String value) {
    final normalized = value.toLowerCase().replaceAll('_', '').replaceAll('-', '');

    switch (normalized) {
      case 'visual':
      case 'vfr':
        return ReportingPointType.visual;
      case 'compulsory':
      case 'mandatory':
        return ReportingPointType.compulsory;
      case 'enroute':
      case 'route':
        return ReportingPointType.enroute;
      case 'terminal':
      case 'term':
        return ReportingPointType.terminal;
      default:
        return ReportingPointType.visual;
    }
  }

  /// Get icon symbol for map display
  String get iconSymbol {
    switch (this) {
      case ReportingPointType.visual:
        return '▲'; // Triangle for visual points
      case ReportingPointType.compulsory:
        return '▲'; // Filled triangle for compulsory
      case ReportingPointType.enroute:
        return '△'; // Triangle outline for en-route
      case ReportingPointType.terminal:
        return '⬟'; // Pentagon for terminal points
    }
  }

  /// Get color for map display
  int get color {
    switch (this) {
      case ReportingPointType.visual:
        return 0xFF9C27B0; // Purple
      case ReportingPointType.compulsory:
        return 0xFFE91E63; // Pink - more prominent
      case ReportingPointType.enroute:
        return 0xFF673AB7; // Deep purple
      case ReportingPointType.terminal:
        return 0xFF3F51B5; // Indigo
    }
  }
}

/// Altitude restrictions for reporting points
class AltitudeRestriction {
  final int? minimumAltitude; // feet
  final int? maximumAltitude; // feet
  final String? restriction; // e.g., "at or below", "at or above"

  const AltitudeRestriction({
    this.minimumAltitude,
    this.maximumAltitude,
    this.restriction,
  });

  factory AltitudeRestriction.fromJson(Map<String, dynamic> json) {
    return AltitudeRestriction(
      minimumAltitude: (json['minimum'] as num?)?.toInt(),
      maximumAltitude: (json['maximum'] as num?)?.toInt(),
      restriction: json['restriction'] as String?,
    );
  }

  /// Get human-readable description
  String get description {
    if (minimumAltitude != null && maximumAltitude != null) {
      return 'Alt: ${minimumAltitude}ft - ${maximumAltitude}ft';
    } else if (minimumAltitude != null) {
      return 'Alt: ≥${minimumAltitude}ft';
    } else if (maximumAltitude != null) {
      return 'Alt: ≤${maximumAltitude}ft';
    } else if (restriction != null) {
      return 'Alt: $restriction';
    }
    return '';
  }
}