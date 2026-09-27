import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:varanasi_core/varanasi_core.dart';

void main() {
  late TokenStore tokens;
  late List<http.Request> sent;

  ApiClient clientReturning(http.Response Function(http.Request) respond) {
    sent = [];
    return ApiClient(
      baseUrl: Uri.parse('https://api.example.test'),
      tokens: tokens,
      httpClient: MockClient((request) async {
        sent.add(request);
        return respond(request);
      }),
    );
  }

  http.Response json(int status, Object body, {Map<String, String>? headers}) =>
      http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json', ...?headers},
      );

  setUp(() => tokens = TokenStore());

  test(
    'adds bearer token and a valid correlation ID to every request',
    () async {
      tokens.setAccessToken('tok-123');
      final client = clientReturning((_) => json(200, {'status': 'ok'}));

      final response = await client.get('/health');

      expect(response.json, {'status': 'ok'});
      final headers = sent.single.headers;
      expect(headers['authorization'], 'Bearer tok-123');
      expect(headers['x-correlation-id'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(sent.single.url.toString(), 'https://api.example.test/health');
    },
  );

  test('omits Authorization when signed out', () async {
    final client = clientReturning((_) => json(200, {}));

    await client.get('/health');

    expect(sent.single.headers.containsKey('authorization'), isFalse);
  });

  test(
    'every POST carries an Idempotency-Key (UUID v4), reused on retry',
    () async {
      final client = clientReturning((_) => json(201, {'id': '1'}));

      await client.post('/api/v1/invoices', body: {'a': 1});
      await client.post(
        '/api/v1/invoices',
        body: {'a': 1},
        idempotencyKey: 'fixed-key',
      );

      expect(
        sent[0].headers['idempotency-key'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(sent[1].headers['idempotency-key'], 'fixed-key');
      expect(jsonDecode(sent[0].body), {'a': 1});
    },
  );

  test('PATCH sends If-Match and a merge-patch body', () async {
    final client = clientReturning(
      (_) => json(200, {}, headers: {'etag': '"5"'}),
    );

    final response = await client.patch(
      '/api/v1/employees/1',
      body: {'x': 1},
      ifMatch: '"4"',
    );

    expect(sent.single.headers['if-match'], '"4"');
    expect(
      sent.single.headers['content-type'],
      startsWith('application/merge-patch+json'),
    );
    expect(response.etag, '"5"');
  });

  test(
    'Problem Details errors become ApiException with field errors',
    () async {
      final client = clientReturning(
        (_) => json(422, {
          'type': 'https://errors.example/validation-failed',
          'title': 'Validation failed',
          'status': 422,
          'code': 'validation_failed',
          'correlation_id': 'req-aa11bb22',
          'errors': [
            {
              'field': 'display_name',
              'code': 'required',
              'message': 'Display name is required.',
            },
          ],
        }),
      );

      await expectLater(
        client.post('/api/v1/employees', body: {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'validation_failed')
              .having((e) => e.correlationId, 'correlationId', 'req-aa11bb22')
              .having(
                (e) => e.fieldErrors.single.field,
                'field',
                'display_name',
              ),
        ),
      );
    },
  );

  test('a 401 signs the user out', () async {
    tokens.setAccessToken('expired');
    final client = clientReturning(
      (_) => json(401, {'code': 'unauthenticated'}),
    );

    await expectLater(client.get('/api/v1/me'), throwsA(isA<ApiException>()));
    expect(tokens.isAuthenticated, isFalse);
  });

  test('network failures become a network_error ApiException', () async {
    final client = ApiClient(
      baseUrl: Uri.parse('https://api.example.test'),
      tokens: tokens,
      httpClient: MockClient(
        (_) async => throw http.ClientException('offline'),
      ),
    );

    await expectLater(
      client.get('/health'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'network_error'),
      ),
    );
  });
}
