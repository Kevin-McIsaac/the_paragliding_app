import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_paragliding_app/utils/preferences_helper.dart';

/// Covers the `cesium_base_map` vocabulary fix (#302).
///
/// The key is read by `assets/cesium/cesium.js`, which matches it against a
/// Cesium imagery provider *display name* and silently falls back to the first
/// available provider on no match. The old slugs (`satellite`, `openstreetmap`,
/// `hybrid`) matched nothing, so they are dropped on read - which reproduces the
/// fallback users have been getting all along, in both token modes.
void main() {
  group('PreferencesHelper.getCesiumBaseMap', () {
    test('returns null and stores nothing when unset', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await PreferencesHelper.getCesiumBaseMap(), isNull);

      // No lazy-seeded default: an unset key must stay unset so Cesium picks its
      // own first provider, which differs between the free and premium lists.
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.containsKey(PreferencesHelper.cesiumBaseMapKey), isFalse);
    });

    test('drops a legacy slug and removes the key', () async {
      for (final legacy in ['satellite', 'openstreetmap', 'hybrid']) {
        SharedPreferences.setMockInitialValues({
          PreferencesHelper.cesiumBaseMapKey: legacy,
        });

        expect(
          await PreferencesHelper.getCesiumBaseMap(),
          isNull,
          reason: '$legacy matches no Cesium provider name',
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        expect(
          prefs.containsKey(PreferencesHelper.cesiumBaseMapKey),
          isFalse,
          reason: '$legacy should be migrated away, not re-read every launch',
        );
      }
    });

    test('returns a real provider name untouched', () async {
      SharedPreferences.setMockInitialValues({
        PreferencesHelper.cesiumBaseMapKey: 'Sentinel-2',
      });

      expect(await PreferencesHelper.getCesiumBaseMap(), 'Sentinel-2');

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.getString(PreferencesHelper.cesiumBaseMapKey), 'Sentinel-2');
    });

    test('round-trips a value written by the in-map picker', () async {
      SharedPreferences.setMockInitialValues({});

      await PreferencesHelper.setCesiumBaseMap('Google Maps 2D Satellite');

      expect(
        await PreferencesHelper.getCesiumBaseMap(),
        'Google Maps 2D Satellite',
      );
    });
  });
}
