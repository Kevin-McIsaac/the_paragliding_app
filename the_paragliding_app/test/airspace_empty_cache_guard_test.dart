import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_paragliding_app/services/airspace_geojson_service.dart';

/// Airspace is only ever downloaded when the user picks a country, so an empty cache is
/// the normal state - and finding that out used to cost ~2s on *every* viewport change
/// (issue #347). Almost all of it was opening a database with no rows in it: ~1362ms in
/// the lazy open, which the pipeline metrics billed to "database_query", and only 612ms
/// in the query itself.
///
/// The guard reads the selected-country list from SharedPreferences - free, and already
/// in memory on this path - and returns before the database is touched at all.
///
/// These tests work because path_provider has no implementation under `flutter test`:
/// reaching the database means calling getApplicationDocumentsDirectory(), which throws.
/// So "returns cleanly" and "touched the database" are directly distinguishable, with no
/// mocking. Reverting the guard turns the first test red with a MissingPluginException.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The bounds from the issue: Perth, Western Australia.
  final perth = fm.LatLngBounds(
    const LatLng(-32.36228712305954, 115.58068411690849),
    const LatLng(-31.549561021093186, 116.14569527762279),
  );

  Future<List<fm.Polygon>> fetchForPerth() {
    return AirspaceGeoJsonService.instance.fetchAirspacePolygonsDirect(
      perth,
      0.5,
      const {},
      const {},
      10000.0,
      true,
    );
  }

  group('empty airspace cache', () {
    test('no countries selected returns nothing without opening the database', () async {
      SharedPreferences.setMockInitialValues({});

      // Without the guard this throws instead of returning: the call reaches
      // `await database`, which needs path_provider.
      expect(await fetchForPerth(), isEmpty);
    });

    test('an empty country list is treated the same as no key at all', () async {
      SharedPreferences.setMockInitialValues({
        'airspace_selected_countries': <String>[],
      });

      expect(await fetchForPerth(), isEmpty);
    });
  });

  group('the guard does not over-block', () {
    test('a selected country still reaches the database', () async {
      SharedPreferences.setMockInitialValues({
        'airspace_selected_countries': <String>['AU'],
      });

      // The complement of the tests above, and the reason they prove anything: with a
      // country selected the guard must fall through to the real path. Under
      // `flutter test` that means path_provider throws - which is exactly the signal
      // that the database was reached rather than skipped.
      //
      // Without this, a guard that returned [] unconditionally would pass every other
      // test in this file while silently blanking the overlay for real users.
      await expectLater(fetchForPerth(), throwsA(anything));
    });
  });
}
