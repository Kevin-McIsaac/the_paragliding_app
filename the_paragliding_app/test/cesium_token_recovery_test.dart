import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_paragliding_app/presentation/widgets/cesium_3d_map_inappwebview.dart'
    show isCesiumHost;
import 'package:the_paragliding_app/services/cesium_token_validator.dart';
import 'package:the_paragliding_app/utils/preferences_helper.dart';

/// A user's own Ion token shadows the app's build-time token. When Ion starts
/// rejecting it, the 3D map used to go blank permanently: the validated flag was
/// only ever written `true`, so a dead token kept reading "Active" and kept being
/// sent (#300).
///
/// Two pieces of that recovery are unit-testable without a WebView.
void main() {
  group('isCesiumHost', () {
    test('accepts the hosts that serve Ion assets', () {
      expect(isCesiumHost(Uri.parse('https://api.cesium.com/v1/assets/3954')), isTrue);
      expect(isCesiumHost(Uri.parse('https://assets.ion.cesium.com/3954/tile.png')), isTrue);
      expect(isCesiumHost(Uri.parse('https://cesium.com/downloads/Cesium.js')), isTrue);
    });

    test('is case-insensitive about the host', () {
      expect(isCesiumHost(Uri.parse('https://API.Cesium.COM/v1/me')), isTrue);
    });

    test('rejects a lookalike domain that merely ends in the same letters', () {
      // The reason the suffix check keeps its leading dot. A bare
      // endsWith('cesium.com') would let this host discard the user's token.
      expect(isCesiumHost(Uri.parse('https://notcesium.com/tile.png')), isFalse);
      expect(isCesiumHost(Uri.parse('https://evilcesium.com/tile.png')), isFalse);
    });

    test('rejects unrelated hosts and URLs with no host', () {
      expect(isCesiumHost(Uri.parse('https://tile.openstreetmap.org/1/2/3.png')), isFalse);
      expect(isCesiumHost(Uri.parse('https://api.core.openaip.net/api/airspaces')), isFalse);
      expect(isCesiumHost(Uri.parse('about:blank')), isFalse);
      expect(isCesiumHost(null), isFalse);
    });
  });

  group('setCesiumTokenValidated', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('records a date when validation succeeds', () async {
      await PreferencesHelper.setCesiumTokenValidated(true);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isTrue);
      expect(await PreferencesHelper.getCesiumTokenValidationDate(), isNotNull);
    });

    test('clears the date when validation fails', () async {
      // The date means "last validated successfully". Failures reach this method
      // too, and stamping the current time onto one would leave a token that just
      // failed looking freshly validated.
      await PreferencesHelper.setCesiumTokenValidated(true);
      expect(await PreferencesHelper.getCesiumTokenValidationDate(), isNotNull);

      await PreferencesHelper.setCesiumTokenValidated(false);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isFalse);
      expect(await PreferencesHelper.getCesiumTokenValidationDate(), isNull);
    });
  });

  /// The other half of #306. Validating against imagery is only half the fix:
  /// the settings card also re-checks the token whenever it is expanded, so a
  /// user offline in a launch paddock runs that check constantly. If a failed
  /// request counted as a rejection, opening the card without a signal would
  /// demote a perfectly good token and blank the 3D map until they retyped it.
  group('recordValidation', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('stores a pass', () async {
      expect(await CesiumTokenValidator.recordValidation(CesiumTokenStatus.valid), isTrue);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isTrue);
      expect(await PreferencesHelper.getCesiumTokenValidationDate(), isNotNull);
    });

    test('stores a rejection', () async {
      await PreferencesHelper.setCesiumTokenValidated(true);

      expect(await CesiumTokenValidator.recordValidation(CesiumTokenStatus.invalid), isFalse);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isFalse);
    });

    test('leaves a validated token alone when Ion is unreachable', () async {
      await PreferencesHelper.setCesiumTokenValidated(true);
      final validatedOn = await PreferencesHelper.getCesiumTokenValidationDate();

      expect(await CesiumTokenValidator.recordValidation(CesiumTokenStatus.unreachable), isNull);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isTrue);
      expect(await PreferencesHelper.getCesiumTokenValidationDate(), validatedOn);
    });

    test('leaves a rejected token rejected when Ion is unreachable', () async {
      // The guard must not resurrect a token either - "we could not ask" is not
      // evidence in favour any more than it is evidence against.
      await PreferencesHelper.setCesiumTokenValidated(false);

      expect(await CesiumTokenValidator.recordValidation(CesiumTokenStatus.unreachable), isNull);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isFalse);
    });

    test('writes nothing at all when no token has ever been checked', () async {
      expect(await CesiumTokenValidator.recordValidation(CesiumTokenStatus.unreachable), isNull);

      expect(await PreferencesHelper.getCesiumTokenValidated(), isNull);
    });
  });
}
