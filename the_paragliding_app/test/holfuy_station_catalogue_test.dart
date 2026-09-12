import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:the_paragliding_app/data/models/holfuy_station_catalogue.dart';
import 'package:the_paragliding_app/data/models/weather_station.dart';
import 'package:the_paragliding_app/data/models/weather_station_source.dart';

/// The parse from the published Holfuy station file into stations the map can
/// draw. Pure: no network, no disk.
void main() {
  String fileWith(List<Map<String, dynamic>> stations) => jsonEncode({
        'generated_utc': '2026-09-12T00:18:24Z',
        'source': 'holfuy',
        'attribution': 'Holfuy',
        'attribution_url': 'https://holfuy.com/',
        'licence': 'used with permission',
        'stations': stations,
      });

  Map<String, dynamic> station({
    String id = '142',
    Object? name = 'THPK Ersfjord',
    Object? lat = 69.70017,
    Object? lon = 18.63842,
    Object? alt = 130,
    String country = 'NO',
    Object? url,
  }) =>
      {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
        'alt': alt,
        'country': country,
        'url': url ?? 'https://holfuy.com/en/weather/$id',
      };

  test('parses names, altitudes and coordinates', () {
    final catalogue = HolfuyStationCatalogue.parse(fileWith([
      station(),
      station(id: '1222', name: 'Pointy Knob', lat: 39.002045, lon: -79.467939),
    ]));

    expect(catalogue.stations, hasLength(2));
    expect(catalogue.isComplete, isTrue);
    expect(catalogue.generatedUtc, '2026-09-12T00:18:24Z');
    expect(catalogue.attribution, 'Holfuy');
    expect(catalogue.licence, 'used with permission');

    final first = catalogue.stations.first;
    expect(first.source, WeatherStationSource.holfuy);
    expect(first.name, 'THPK Ersfjord');
    expect(first.latitude, 69.70017);
    expect(first.longitude, 18.63842);
    expect(first.elevation, 130);
    expect(first.dataUrl, 'https://holfuy.com/en/weather/142');
    expect(first.windData, isNull);
  });

  test('a numeric Holfuy id is not labelled a Marine Buoy', () {
    // The id-pattern helper would say "Marine Buoy" for every Holfuy station,
    // because every Holfuy id is numeric. The parser sets the type explicitly;
    // this is the regression that keeps it that way.
    final parsed = HolfuyStationCatalogue.parse(fileWith([station()])).stations.single;

    expect(parsed.observationType, 'Holfuy launch station');
    expect(WeatherStation.inferObservationType('142'), 'Marine Buoy');
  });

  test('drops unusable coordinates instead of placing them at 0,0', () {
    final catalogue = HolfuyStationCatalogue.parse(fileWith([
      station(),
      // "NaN"/"Infinity" rather than the double literals: these arrive as JSON
      // strings, and double.tryParse turns them into the non-finite values the
      // parser must reject.
      station(id: 'nan', lat: 'NaN'),
      station(id: 'inf', lon: 'Infinity'),
      station(id: 'range', lat: 91.0),
      station(id: 'text', lat: 'north', lon: 'east'),
      station(id: 'missing', lat: null, lon: null),
    ]));

    expect(catalogue.stations.map((s) => s.id), ['142']);
    // Skipped rows are counted, not silently dropped: a file that lost rows on
    // the way in is not evidence those stations were withdrawn.
    expect(catalogue.skipped, 5);
    expect(catalogue.isComplete, isFalse);
    expect(
      catalogue.stations.any((s) => s.latitude == 0.0 && s.longitude == 0.0),
      isFalse,
    );
  });

  test('a station with no id is dropped', () {
    final catalogue = HolfuyStationCatalogue.parse(fileWith([
      station(id: ''),
      station(),
    ]));

    expect(catalogue.stations, hasLength(1));
    expect(catalogue.skipped, 1);
  });

  test('a missing name is null and a missing url falls back to the page', () {
    final parsed = HolfuyStationCatalogue.parse(
      fileWith([station(name: null, url: '')]),
    ).stations.single;

    expect(parsed.name, isNull);
    expect(parsed.dataUrl, 'https://holfuy.com/en/weather/142');
  });

  test('accepts numeric strings for coordinates', () {
    final parsed = HolfuyStationCatalogue.parse(
      fileWith([station(lat: '69.70017', lon: '18.63842', alt: '130')]),
    ).stations.single;

    expect(parsed.latitude, 69.70017);
    expect(parsed.longitude, 18.63842);
    expect(parsed.elevation, 130);
  });

  test('rejects a payload that is not the expected shape', () {
    expect(
      () => HolfuyStationCatalogue.parse('<html>nope</html>'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => HolfuyStationCatalogue.parse('{"no_stations": []}'),
      throwsA(isA<FormatException>()),
    );
  });
}
