import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_paragliding_app/services/openaip_service.dart';

/// Whether airspace is drawn used to be stored twice, with opposite defaults:
///
///   nearby_sites_airspace_enabled  (Sites screen)   default TRUE  -> the checkbox
///   openaip_airspace_enabled       (OpenAipService) default FALSE -> the renderer
///
/// So a fresh install showed a ticked "Airspace" box over a map that never drew
/// any, and the only escape was to un-tick and re-tick the filter - which is
/// exactly what a user hit after downloading 1,819 Australian airspaces and
/// seeing nothing.
///
/// OpenAipService is now the single source of truth, defaulting to on. These
/// tests cover the migration, because simply changing the default is not enough:
/// the old code persisted the default the first time anything read it, so every
/// existing install already has `false` written to disk.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const serviceKey = 'openaip_airspace_enabled';
  const legacyKey = 'nearby_sites_airspace_enabled';
  const migratedKey = 'openaip_airspace_enabled_migrated';

  group('airspace enabled migration', () {
    test('a fresh install defaults to on', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await OpenAipService.instance.isAirspaceEnabled(), isTrue);
    });

    test(
      'the reported bug: ticked checkbox, renderer off, resolves to on',
      () async {
        // The exact state that produced "the toggle was checked but no airspace
        // displayed" - and the state every upgrading install is in.
        SharedPreferences.setMockInitialValues({
          legacyKey: true,
          serviceKey: false,
        });

        expect(await OpenAipService.instance.isAirspaceEnabled(), isTrue);
      },
    );

    test('a deliberate opt-out is preserved', () async {
      // Un-ticking the box is the only way the legacy key becomes false, so it
      // is a real choice and must survive the migration.
      SharedPreferences.setMockInitialValues({
        legacyKey: false,
        serviceKey: false,
      });

      expect(await OpenAipService.instance.isAirspaceEnabled(), isFalse);
    });

    test('the legacy key is removed once migrated', () async {
      SharedPreferences.setMockInitialValues({legacyKey: true});

      await OpenAipService.instance.isAirspaceEnabled();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(legacyKey), isFalse);
      expect(prefs.getBool(migratedKey), isTrue);
      expect(prefs.getBool(serviceKey), isTrue);
    });

    test('migration does not re-run and overwrite a later choice', () async {
      // Turning airspace off after upgrading must stick. If the migration fired
      // again it would resurrect the legacy value on the next read.
      SharedPreferences.setMockInitialValues({legacyKey: true});
      final service = OpenAipService.instance;

      expect(await service.isAirspaceEnabled(), isTrue);

      await service.setAirspaceEnabled(false);
      expect(await service.isAirspaceEnabled(), isFalse);
      expect(await service.isAirspaceEnabled(), isFalse);
    });

    test('reading does not persist the default', () async {
      // The old read-time write is why changing the default could not fix
      // existing installs on its own. A read must stay a read.
      SharedPreferences.setMockInitialValues({migratedKey: true});

      await OpenAipService.instance.isAirspaceEnabled();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.containsKey(serviceKey),
        isFalse,
        reason: 'isAirspaceEnabled() wrote the default to disk on a plain read',
      );
    });
  });
}
