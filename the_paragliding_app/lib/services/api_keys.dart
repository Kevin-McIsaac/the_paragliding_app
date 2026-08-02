import 'logging_service.dart';

/// Centralized API key management service
///
/// Keys are compile-time constants supplied by `--dart-define`: locally via
/// `--dart-define-from-file=env.json` (gitignored), and in CI from repository
/// secrets. See README_API_KEYS.md.
///
/// They are deliberately **not** Flutter assets. `.env` used to be listed under
/// `assets:` in pubspec.yaml, which copied the real keys verbatim into every
/// build - an `.aab` is a zip, so anyone could read them out of a published
/// release without reverse engineering anything.
///
/// dart-define is better but is still not secrecy: these values are compiled
/// into `libapp.so` and can be recovered with `strings`. Restrict each key at
/// the provider (package name, signing fingerprint, scope) and treat anything
/// shipped in a client app as public.
///
/// Usage:
/// ```dart
/// final apiKey = ApiKeys.ffvlApiKey;
/// ```
class ApiKeys {
  /// FFVL (French Free Flight Federation) Weather API Key
  static const String ffvlApiKey = String.fromEnvironment('FFVL_API_KEY');

  /// OpenAIP API Key (optional, user-configurable in app settings)
  static const String openAipApiKey = String.fromEnvironment('OPENAIP_API_KEY');

  /// Cesium Ion Access Token (optional, for 3D map visualization)
  static const String cesiumIonToken = String.fromEnvironment('CESIUM_ION_TOKEN');

  /// Log which keys are configured, and warn about the one the app needs.
  ///
  /// Called once at startup. This is the quickest way to tell whether a build
  /// picked up its keys - a release built without `--dart-define` reports every
  /// key as unconfigured rather than failing loudly.
  static void logStatus() {
    LoggingService.structured('API_KEYS_STATUS', {
      'ffvl_configured': ffvlApiKey.isNotEmpty,
      'openaip_configured': openAipApiKey.isNotEmpty,
      'cesium_configured': cesiumIonToken.isNotEmpty,
      'source': ffvlApiKey.isNotEmpty ? 'dart-define' : 'none',
    });

    if (ffvlApiKey.isEmpty) {
      LoggingService.warning(
          'No FFVL API key. Pass --dart-define-from-file=env.json (see README_API_KEYS.md)');
    }
  }
}
