import 'package:flutter_test/flutter_test.dart';
import 'package:the_paragliding_app/data/models/weather_station.dart';
import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/data/models/wind_data.dart';
import 'package:the_paragliding_app/presentation/screens/nearby_sites_screen.dart';

/// The map's per-provider loading chip used to spin forever.
///
/// WU PWS queues its background passes. The screen starts a fetch, gets its
/// stations straight from cache, and the provider's pass is queued behind
/// another one - so by the time that pass reports terminal, the *next* fetch has
/// already cleared `_providersActuallyLoading`. The terminal push was then read
/// as a *start* whenever the new viewport held no stations
/// (`stationCount == 0`), which wrote a loading entry no later event would
/// clear.
///
/// Seen live 2026-09-12 on Android 1.0.13+26 and on Linux desktop: the map sat
/// on "WU PWS" with its spinner turning and ~130% CPU going into repainting it,
/// while the app itself was healthy - the isolate answered the VM service, and
/// no app code was executing. WU's data path was fine throughout; only the
/// overlay's bookkeeping was stuck.
void main() {
  ProviderProgressEvent classify({
    bool isAlreadyLoading = false,
    bool hasVisibleState = false,
    bool success = true,
    int stationCount = 0,
    bool passComplete = false,
  }) =>
      NearbySitesScreenState.classifyProviderEvent(
        isAlreadyLoading: isAlreadyLoading,
        hasVisibleState: hasVisibleState,
        success: success,
        stationCount: stationCount,
        passComplete: passComplete,
      );

  group('a terminal provider event is never mistaken for a start', () {
    test('terminal push, no stations, nothing tracked: nothing to do', () {
      // The regression itself: this is the event that used to set the chip to
      // loading, with no event left to clear it.
      expect(classify(passComplete: true), ProviderProgressEvent.ignore);
    });

    test('terminal push, no stations, provider tracked: completes', () {
      expect(
        classify(
          passComplete: true,
          isAlreadyLoading: true,
          hasVisibleState: true,
        ),
        ProviderProgressEvent.complete,
      );
    });

    test('terminal push while the provider shows its dismiss tick: completes',
        () {
      // _providersActuallyLoading loses the provider when the tick's timer
      // fires; _providerStates can still hold it when the next push lands.
      expect(
        classify(passComplete: true, hasVisibleState: true),
        ProviderProgressEvent.complete,
      );
    });

    test('a cache hit reporting terminal must not flash a tick', () {
      expect(
        classify(passComplete: true, stationCount: 5),
        ProviderProgressEvent.ignore,
      );
    });

    test('a failed provider reports terminal, it does not start', () {
      expect(
        classify(passComplete: true, success: false, isAlreadyLoading: true),
        ProviderProgressEvent.complete,
      );
    });
  });

  group('ordinary progress events', () {
    test('a first call with no stations yet is a start', () {
      expect(classify(), ProviderProgressEvent.start);
    });

    test('stations arriving with no API call are a cache hit', () {
      expect(classify(stationCount: 5), ProviderProgressEvent.cacheHit);
    });

    test('an already-loading provider gets no second start', () {
      expect(classify(isAlreadyLoading: true), ProviderProgressEvent.ignore);
    });

    test('a failure is not a start', () {
      expect(classify(success: false), ProviderProgressEvent.ignore);
    });
  });

  // Providers hand the screen one source's stations at a time: intermediate
  // pushes carry only what changed, the terminal push carries that provider's
  // full list. The screen used to replace everything with a cumulative list
  // instead, re-processing every station of every provider on every push.
  group('station updates merge per source', () {
    WeatherStation station(WeatherStationSource source, String id,
            {double? speed}) =>
        WeatherStation(
          id: id,
          source: source,
          latitude: -32.0,
          longitude: 116.0,
          windData: speed == null
              ? null
              : WindData(
                  speedKmh: speed,
                  directionDegrees: 90,
                  timestamp: DateTime(2026, 9, 12),
                ),
        );

    test('a delta merges by key and leaves every other station alone', () {
      final current = [
        station(WeatherStationSource.weatherUndergroundPws, 'A', speed: 10),
        station(WeatherStationSource.weatherUndergroundPws, 'B', speed: 11),
        station(WeatherStationSource.awcMetar, 'C', speed: 12),
      ];

      final merged = NearbySitesScreenState.applyStationUpdate(
        current,
        WeatherStationSource.weatherUndergroundPws,
        [station(WeatherStationSource.weatherUndergroundPws, 'A', speed: 25)],
        replaceSource: false,
      );

      expect(
        merged.map((s) => s.key).toSet(),
        {
          'weatherUndergroundPws:A',
          'weatherUndergroundPws:B',
          'awcMetar:C',
        },
        reason: 'a delta must not drop the stations it does not mention',
      );
      expect(
        merged
            .firstWhere((s) => s.key == 'weatherUndergroundPws:A')
            .windData!
            .speedKmh,
        25,
        reason: 'and it must update the one it does',
      );
    });

    test('a terminal update replaces its own source and nothing else', () {
      final current = [
        station(WeatherStationSource.weatherUndergroundPws, 'A'),
        station(WeatherStationSource.weatherUndergroundPws, 'B'),
        station(WeatherStationSource.awcMetar, 'C'),
      ];

      final merged = NearbySitesScreenState.applyStationUpdate(
        current,
        WeatherStationSource.weatherUndergroundPws,
        [station(WeatherStationSource.weatherUndergroundPws, 'B')],
        replaceSource: true,
      );

      expect(
        merged.map((s) => s.key).toSet(),
        {'weatherUndergroundPws:B', 'awcMetar:C'},
        reason: 'the terminal list is the source whole, so A is gone',
      );
    });
  });
}
