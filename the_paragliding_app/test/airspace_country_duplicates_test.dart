import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_paragliding_app/services/airspace_country_service.dart';

/// The airspace country selector appended the country code without checking whether it
/// was already there, so a real prefs file ended up holding ['AU','AT','AT','BE','AU'].
///
/// That is not merely untidy. Every caller removes a country with `List.remove`, which
/// drops only the *first* occurrence, so a country selected twice survived being removed:
/// it stayed selected in the UI, and it kept the airspace overlay on its slow path
/// instead of the empty-cache skip added in #351.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = 'airspace_selected_countries';
  final service = AirspaceCountryService.instance;

  group('reading', () {
    test('duplicates already on disk are not returned twice', () async {
      // The exact contents of the prefs file that exposed this.
      SharedPreferences.setMockInitialValues({
        key: <String>['AU', 'AT', 'AT', 'BE', 'AU'],
      });

      expect(await service.getSelectedCountries(), ['AU', 'AT', 'BE']);
    });

    test('an unduplicated list is returned unchanged, in order', () async {
      SharedPreferences.setMockInitialValues({
        key: <String>['AU', 'AT', 'BE'],
      });

      expect(await service.getSelectedCountries(), ['AU', 'AT', 'BE']);
    });
  });

  group('writing', () {
    test('a country selected twice is stored once', () async {
      SharedPreferences.setMockInitialValues({});

      await service.setSelectedCountries(['AU', 'AU', 'AT']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(key), ['AU', 'AT']);
    });
  });

  group('the symptom this caused', () {
    test('a duplicated country can actually be removed', () async {
      SharedPreferences.setMockInitialValues({
        key: <String>['AU', 'AT', 'AU'],
      });

      // Exactly what airspace_country_selector.dart does when you remove a country:
      // read, List.remove, write back. With duplicates present, `remove` dropped only
      // the first 'AU' and the second one silently kept the country selected.
      final selected = await service.getSelectedCountries();
      selected.remove('AU');
      await service.setSelectedCountries(selected);

      expect(await service.getSelectedCountries(), isNot(contains('AU')));
    });

    test('removing the last country leaves an empty list, so the skip can fire', () async {
      // #351 skips the whole airspace pipeline when no country is selected. A surviving
      // duplicate defeated that, which is why this is worth asserting directly.
      SharedPreferences.setMockInitialValues({
        key: <String>['AU', 'AU'],
      });

      final selected = await service.getSelectedCountries();
      selected.remove('AU');
      await service.setSelectedCountries(selected);

      expect(await service.getSelectedCountries(), isEmpty);
    });
  });
}
