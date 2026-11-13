import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:the_paragliding_app/data/models/weather_station_source.dart';
import 'package:the_paragliding_app/services/weather_station_service.dart';

/// The Pioupiou source became OpenWindMap. The enabled flag must survive the
/// rename, so a pilot who turned that layer off does not get it back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const newKey = 'weather_provider_openWindMap_enabled';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('copies the old Pioupiou setting to OpenWindMap', () async {
    SharedPreferences.setMockInitialValues({
      WeatherStationService.legacyPioupiouEnabledKey: false,
    });

    await WeatherStationService.migrateLegacyProviderPreferences();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(newKey), isFalse);
    // The old key stays for a rollback.
    expect(
      prefs.getBool(WeatherStationService.legacyPioupiouEnabledKey),
      isFalse,
    );
  });

  test('does not overwrite an existing OpenWindMap setting', () async {
    SharedPreferences.setMockInitialValues({
      WeatherStationService.legacyPioupiouEnabledKey: false,
      newKey: true,
    });

    await WeatherStationService.migrateLegacyProviderPreferences();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(newKey), isTrue);
  });

  test('reads the legacy key before migration', () async {
    SharedPreferences.setMockInitialValues({
      WeatherStationService.legacyPioupiouEnabledKey: false,
    });

    final prefs = await SharedPreferences.getInstance();

    expect(
      WeatherStationService.isProviderEnabledFromPrefs(
        prefs,
        WeatherStationSource.openWindMap,
      ),
      isFalse,
    );
  });

  test('defaults to enabled for a new install', () async {
    final prefs = await SharedPreferences.getInstance();

    expect(
      WeatherStationService.isProviderEnabledFromPrefs(
        prefs,
        WeatherStationSource.openWindMap,
      ),
      isTrue,
    );
  });

  test('setProviderEnabled writes the new key and reads it back', () async {
    await WeatherStationService.setProviderEnabled(
      WeatherStationSource.openWindMap,
      false,
    );

    expect(
      await WeatherStationService.isProviderEnabled(
        WeatherStationSource.openWindMap,
      ),
      isFalse,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(newKey), isFalse);
  });
}
