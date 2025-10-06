import 'wind_data.dart';
import 'weather_station_source.dart';

/// Weather station from various data providers (METAR, NOAA CDO, etc.)
/// Represents an actual meteorological station with location and weather data
class WeatherStation {
  /// Unique station identifier
  final String id;

  /// Data source/provider for this station
  final WeatherStationSource source;

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

  /// Dataset ID (for providers like NOAA CDO that have multiple datasets)
  final String? datasetId;

  const WeatherStation({
    required this.id,
    required this.source,
    this.name,
    required this.latitude,
    required this.longitude,
    this.windData,
    this.elevation,
    this.datasetId,
  });

  /// Create a copy with updated wind data
  WeatherStation copyWith({WindData? windData}) {
    return WeatherStation(
      id: id,
      source: source,
      name: name,
      latitude: latitude,
      longitude: longitude,
      windData: windData ?? this.windData,
      elevation: elevation,
      datasetId: datasetId,
    );
  }

  /// Create a unique key for this station based on source and ID
  /// Ensures uniqueness across multiple providers
  String get key => '${source.name}:$id';

  @override
  String toString() {
    return 'WeatherStation(source: ${source.name}, id: $id, name: $name, lat: $latitude, lon: $longitude, elevation: $elevation)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeatherStation && other.source == source && other.id == id;
  }

  @override
  int get hashCode => Object.hash(source, id);
}
