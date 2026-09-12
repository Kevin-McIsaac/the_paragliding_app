import 'dart:convert';

import 'weather_station.dart';
import 'weather_station_source.dart';

/// The published Holfuy station catalogue, parsed into [WeatherStation]s.
///
/// Positions, names and altitudes only. Holfuy has no discovery endpoint - no
/// WU-style "what is near this point" and no bulk list - so the app cannot find
/// these stations for itself; the catalogue is what makes them displayable at
/// all. Readings are fetched later, one station at a time, by the provider.
///
/// The parse mirrors `src/holfuy.py:app_stations_payload`, which writes the
/// file: `{"stations": [{"id", "name", "lat", "lon", "alt", "country", "url"}]}`
/// plus attribution and licence keys that travel with the data.
class HolfuyStationCatalogue {
  final String? generatedUtc;
  final String? attribution;
  final String? attributionUrl;
  final String? licence;

  /// Stations with coordinates the map can draw.
  final List<WeatherStation> stations;

  /// Entries dropped because they carried no usable position.
  ///
  /// Counted rather than silently ignored for the same reason the producer
  /// counts them: a catalogue that lost rows on the way in is not evidence that
  /// those stations were withdrawn.
  final int skipped;

  const HolfuyStationCatalogue({
    required this.stations,
    this.generatedUtc,
    this.attribution,
    this.attributionUrl,
    this.licence,
    this.skipped = 0,
  });

  /// Whether every entry in the file survived parsing.
  bool get isComplete => skipped == 0;

  int get length => stations.length;

  static const String defaultAttribution = 'Holfuy';
  static const String defaultAttributionUrl = 'https://holfuy.com/';

  /// Parse the published file.
  ///
  /// Throws [FormatException] when the payload is not the expected object with
  /// a `stations` list - a truncated download or an HTML error page must be a
  /// loud failure at the call site that validates a download, not an empty map.
  /// A single unusable *entry*, by contrast, is skipped and counted: one bad
  /// row must not make the whole catalogue unreadable.
  static HolfuyStationCatalogue parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const FormatException('Holfuy station file is not valid JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Holfuy station file is not a JSON object');
    }

    final raw = decoded['stations'];
    if (raw is! List) {
      throw const FormatException('Holfuy station file has no "stations" list');
    }

    final stations = <WeatherStation>[];
    var skipped = 0;
    for (final entry in raw) {
      final station = _parseStation(entry);
      if (station == null) {
        skipped++;
        continue;
      }
      stations.add(station);
    }

    return HolfuyStationCatalogue(
      stations: stations,
      generatedUtc: _string(decoded['generated_utc']),
      attribution: _string(decoded['attribution']),
      attributionUrl: _string(decoded['attribution_url']),
      licence: _string(decoded['licence']),
      skipped: skipped,
    );
  }

  /// One station, or null when its position cannot be drawn.
  ///
  /// A station at 0,0 is never produced by coercion: it would sit off the coast
  /// of Africa, match nothing, and look like coverage.
  static WeatherStation? _parseStation(Object? entry) {
    if (entry is! Map) return null;

    final id = _string(entry['id']);
    if (id == null || id.isEmpty) return null;

    final lat = _finiteDouble(entry['lat']);
    final lon = _finiteDouble(entry['lon']);
    if (lat == null || lon == null) return null;
    if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) return null;

    final name = _string(entry['name']);
    final url = _string(entry['url']);

    return WeatherStation(
      id: id,
      source: WeatherStationSource.holfuy,
      name: (name == null || name.isEmpty) ? null : name,
      latitude: lat,
      longitude: lon,
      elevation: _finiteDouble(entry['alt']),
      // Explicit, because WeatherStation.inferObservationType reads a numeric
      // id as "Marine Buoy" - every Holfuy id is numeric.
      observationType: 'Holfuy launch station',
      dataUrl: (url == null || url.isEmpty)
          ? 'https://holfuy.com/en/weather/$id'
          : url,
    );
  }

  static String? _string(Object? value) {
    if (value is String) return value;
    if (value == null) return null;
    return value.toString();
  }

  /// A real, finite number, from a JSON number or a numeric string.
  static double? _finiteDouble(Object? value) {
    final double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(value);
    } else {
      parsed = null;
    }
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }
}
