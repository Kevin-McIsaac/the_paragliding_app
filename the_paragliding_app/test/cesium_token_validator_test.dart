import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:the_paragliding_app/services/cesium_token_validator.dart';

/// #306: validation used to call `/v1/me`, the account *profile* endpoint. Ion
/// tokens can be scoped to a list of assets, so a token that reads the profile
/// happily may still 401 on every imagery tile - the settings card said
/// "Active" while the 3D map stayed blank.
///
/// The probe now hits the request `Cesium.IonImageryProvider.fromAssetId(3954)`
/// actually makes. Responses below are the shapes the live API returns, checked
/// against api.cesium.com.
void main() {
  const token = 'ion-token-for-tests';

  /// Responds with [statusCode]/[body] and records what was asked for.
  MockClient recordingClient(int statusCode, String body, List<http.Request> log) {
    return MockClient((request) async {
      log.add(request);
      return http.Response(body, statusCode);
    });
  }

  tearDown(() => CesiumTokenValidator.client = http.Client());

  group('validateToken request', () {
    test('asks Ion for the imagery asset the map loads, not the profile', () async {
      final requests = <http.Request>[];
      CesiumTokenValidator.client =
          recordingClient(200, '{"type":"IMAGERY"}', requests);

      await CesiumTokenValidator.validateToken(token);

      expect(requests, hasLength(1));
      expect(requests.single.url.toString(),
          'https://api.cesium.com/v1/assets/3954/endpoint');
      expect(requests.single.headers['Authorization'], 'Bearer $token');
    });

    test('does not call Ion at all for an empty token', () async {
      final requests = <http.Request>[];
      CesiumTokenValidator.client = recordingClient(200, '{}', requests);

      expect(await CesiumTokenValidator.validateToken(''),
          CesiumTokenStatus.invalid);
      expect(requests, isEmpty);
    });
  });

  group('validateToken outcomes', () {
    Future<CesiumTokenStatus> respond(int statusCode, [String body = '{}']) {
      CesiumTokenValidator.client =
          MockClient((_) async => http.Response(body, statusCode));
      return CesiumTokenValidator.validateToken(token);
    }

    test('200 means the map will render', () async {
      expect(await respond(200, '{"type":"IMAGERY","url":"https://..."}'),
          CesiumTokenStatus.valid);
    });

    test('401 is a rejected token', () async {
      expect(
          await respond(
              401, '{"code":"INVALID_TOKEN","message":"Invalid access token"}'),
          CesiumTokenStatus.invalid);
    });

    test('403 is a token without assets:read', () async {
      expect(await respond(403), CesiumTokenStatus.invalid);
    });

    test('404 is a token scoped to other assets - the #306 case', () async {
      // Ion hides an out-of-scope asset rather than returning 403, so a naive
      // `statusCode == 401` check would call this token good.
      expect(
          await respond(404,
              '{"code":"ResourceNotFound","message":"Resource Not Found"}'),
          CesiumTokenStatus.invalid);
    });

    test('a server fault says nothing about the token', () async {
      expect(await respond(500), CesiumTokenStatus.unreachable);
      expect(await respond(503), CesiumTokenStatus.unreachable);
    });

    test('a network failure says nothing about the token', () async {
      // The distinction that stops a dropped connection demoting a good token.
      CesiumTokenValidator.client = MockClient(
          (_) async => throw http.ClientException('Connection closed'));

      expect(await CesiumTokenValidator.validateToken(token),
          CesiumTokenStatus.unreachable);
    });

    test('a timeout says nothing about the token', () async {
      // Thrown rather than slept, so the suite does not wait out the real
      // 10-second budget to exercise one catch clause.
      CesiumTokenValidator.client =
          MockClient((_) async => throw TimeoutException('slow'));

      expect(await CesiumTokenValidator.validateToken(token),
          CesiumTokenStatus.unreachable);
    });
  });

  group('maskToken', () {
    test('shows enough of a real token to recognise it', () {
      expect(CesiumTokenValidator.maskToken('eyJhbGciOiJIUzI1NiJ9.abcd'),
          'eyJhbGci...abcd');
    });

    test('reveals nothing about a short token', () {
      expect(CesiumTokenValidator.maskToken('short'), '****...****');
    });
  });
}
