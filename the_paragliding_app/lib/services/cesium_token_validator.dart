import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/logging_service.dart';
import '../utils/preferences_helper.dart';

/// The outcome of a token check.
///
/// A `bool` conflated "Ion rejected this token" with "we could not reach Ion",
/// and every caller wrote the failure straight into `cesium_token_validated` -
/// so a dropped connection demoted a perfectly good token.
enum CesiumTokenStatus {
  /// Ion served the asset. The map will render.
  valid,

  /// Ion rejected the token, or hid the asset from it. The map will not render.
  invalid,

  /// Ion could not be reached, or answered with something unusable. Says
  /// nothing about the token - callers must leave the stored state alone.
  unreachable,
}

/// Service for validating Cesium Ion access tokens
class CesiumTokenValidator {
  static const String _baseUrl = 'https://api.cesium.com/v1';
  static const Duration _timeout = Duration(seconds: 10);

  /// Sentinel-2 imagery. Free tier, and the rung every premium fallback chain
  /// in `assets/cesium/cesium.js` lands on, so a token that cannot read it
  /// cannot draw a map at all.
  static const int _probeAssetId = 3954;

  /// Swapped out by tests. `package:http/testing.dart` ships `MockClient`
  /// inside the http package, so this needs no extra dependency.
  static http.Client client = http.Client();

  /// Checks that [token] can actually fetch the imagery the 3D map loads.
  ///
  /// Validating against the profile endpoint (`/v1/me`) was the bug in #306: an
  /// Ion token can be scoped to a list of assets, so one that reads the account
  /// profile happily may still 401 on every tile. `/v1/assets/{id}/endpoint` is
  /// the exact request `Cesium.IonImageryProvider.fromAssetId` makes.
  static Future<CesiumTokenStatus> validateToken(String token) async {
    if (token.isEmpty) {
      LoggingService.warning('Cesium Token Validation', 'Token is empty');
      return CesiumTokenStatus.invalid;
    }

    final url = '$_baseUrl/assets/$_probeAssetId/endpoint';

    try {
      final response = await client.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_timeout);

      final status = _statusFor(response.statusCode);

      LoggingService.structured('CESIUM_TOKEN_VALIDATION', {
        'asset_id': _probeAssetId,
        'http_status': response.statusCode,
        'result': status.name,
        if (status != CesiumTokenStatus.valid)
          'ion_code': _ionErrorCode(response.body),
      });

      return status;
    } on TimeoutException {
      LoggingService.error('Cesium Token Validation',
          'Request timed out after ${_timeout.inSeconds} seconds');
      return CesiumTokenStatus.unreachable;
    } on http.ClientException catch (e) {
      LoggingService.error('Cesium Token Validation', 'Network error: $e');
      return CesiumTokenStatus.unreachable;
    } catch (e) {
      LoggingService.error('Cesium Token Validation', 'Unexpected error: $e');
      return CesiumTokenStatus.unreachable;
    }
  }

  static CesiumTokenStatus _statusFor(int statusCode) {
    if (statusCode == 200) return CesiumTokenStatus.valid;

    // 404 counts as a rejection, not a server fault: Ion hides assets outside a
    // token's scope rather than returning 403, so a token restricted to some
    // other asset list reports the probe asset as simply not there.
    if (statusCode == 401 || statusCode == 403 || statusCode == 404) {
      return CesiumTokenStatus.invalid;
    }

    return CesiumTokenStatus.unreachable;
  }

  /// Ion error bodies look like `{"code":"INVALID_TOKEN","message":"..."}`.
  /// Best-effort - the body is only ever used for the log line.
  static String? _ionErrorCode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['code'] is String) {
        return decoded['code'] as String;
      }
    } catch (_) {
      // Not JSON, or not shaped like an Ion error. Nothing to report.
    }
    return null;
  }

  /// Records [status] against the stored token, returning the flag now held -
  /// or null when nothing was written.
  ///
  /// `unreachable` deliberately writes nothing: it means we could not ask Ion,
  /// not that the token is bad. Demoting on a dropped connection would put the
  /// settings card back to lying, just in the other direction (#306).
  ///
  /// The failure case *is* written. Only recording successes left a revoked
  /// token reading "Active" and still being sent with every map load (#300).
  static Future<bool?> recordValidation(CesiumTokenStatus status) async {
    if (status == CesiumTokenStatus.unreachable) return null;

    final isValid = status == CesiumTokenStatus.valid;
    await PreferencesHelper.setCesiumTokenValidated(isValid);
    return isValid;
  }

  /// Formats a token for display (shows first 8 and last 4 characters)
  static String maskToken(String token) {
    if (token.length <= 12) {
      return '****...****';
    }

    return '${token.substring(0, 8)}...${token.substring(token.length - 4)}';
  }
}
