import 'wind_data.dart';

/// METAR weather station from aviationweather.gov
/// Represents an actual meteorological station with location and weather data
class WeatherStation {
  /// Unique station identifier
  final String id;

  /// Station name (if available from API)
  final String? name;

  /// Station latitude
  final double latitude;

  /// Station longitude
  final double longitude;

  /// Current wind data for this station (fetched separately)
  final WindData? windData;

  /// Station elevation in meters (if available)
  final double? elevation;

  const WeatherStation({
    required this.id,
    this.name,
    required this.latitude,
    required this.longitude,
    this.windData,
    this.elevation,
  });

  /// Create from generic JSON response (legacy compatibility)
  /// Note: Current implementation uses direct parsing in WeatherStationService
  factory WeatherStation.fromJson(Map<String, dynamic> json) {
    return WeatherStation(
      id: json['id']?.toString() ?? json['wmo_id']?.toString() ?? 'unknown',
      name: json['name'] as String?,
      latitude: (json['latitude'] ?? json['lat'] as num).toDouble(),
      longitude: (json['longitude'] ?? json['lon'] as num).toDouble(),
      elevation: json['elevation'] != null ? (json['elevation'] as num).toDouble() : null,
    );
  }

  /// Create a copy with updated wind data
  WeatherStation copyWith({WindData? windData}) {
    return WeatherStation(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      windData: windData ?? this.windData,
      elevation: elevation,
    );
  }

  /// Create a unique key for this station based on its ID
  String get key => id;

  @override
  String toString() {
    return 'WeatherStation(id: $id, name: $name, lat: $latitude, lon: $longitude, elevation: $elevation)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeatherStation && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
