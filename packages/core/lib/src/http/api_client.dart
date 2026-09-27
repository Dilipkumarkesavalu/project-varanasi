import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../auth/token_store.dart';
import 'api_exception.dart';
import 'ids.dart';

/// A decoded JSON response plus the headers the app may need (`ETag`, correlation ID).
class ApiResponse {
  const ApiResponse({
    required this.status,
    required this.body,
    required this.headers,
  });

  final int status;
  final Object? body;
  final Map<String, String> headers;

  String? get etag => headers['etag'];
  String? get correlationId => headers['x-correlation-id'];
  bool get wasReplayed => headers['idempotent-replayed'] == 'true';

  Map<String, Object?> get json => body as Map<String, Object?>;
}

/// HTTP client for the Varanasi API, applying ADR-0007 on every call:
///
/// - `Authorization: Bearer <token>` when signed in;
/// - a fresh `X-Correlation-ID` per request (logged, and echoed back by the server);
/// - an `Idempotency-Key` on every `POST` (pass the same key when retrying);
/// - `If-Match` for `PATCH` and actions when an [ifMatch] version is given;
/// - errors thrown as [ApiException] parsed from Problem Details;
/// - a `401` clears the [TokenStore], which sends the user back to sign-in.
class ApiClient {
  ApiClient({
    required this._baseUrl,
    required this._tokens,
    http.Client? httpClient,
    Logger? logger,
  }) : _http = httpClient ?? http.Client(),
       _log = logger ?? Logger('varanasi.http');

  final Uri _baseUrl;
  final TokenStore _tokens;
  final http.Client _http;
  final Logger _log;

  Future<ApiResponse> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<ApiResponse> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    String? ifMatch,
  }) => _send(
    'POST',
    path,
    body: body,
    idempotencyKey: idempotencyKey ?? newIdempotencyKey(),
    ifMatch: ifMatch,
  );

  Future<ApiResponse> patch(
    String path, {
    required Object body,
    required String ifMatch,
  }) => _send('PATCH', path, body: body, ifMatch: ifMatch);

  Future<ApiResponse> delete(String path) => _send('DELETE', path);

  void close() => _http.close();

  Future<ApiResponse> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    String? idempotencyKey,
    String? ifMatch,
  }) async {
    final correlationId = newCorrelationId();
    final uri = _baseUrl.replace(
      path: _joinPath(_baseUrl.path, path),
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
    final request = http.Request(method, uri)
      ..headers.addAll({
        'accept': 'application/json',
        'x-correlation-id': correlationId,
        if (_tokens.accessToken case final token?)
          'authorization': 'Bearer $token',
        'idempotency-key': ?idempotencyKey,
        'if-match': ?ifMatch,
      });
    if (body != null) {
      request.headers['content-type'] = method == 'PATCH'
          ? 'application/merge-patch+json'
          : 'application/json';
      request.body = jsonEncode(body);
    }

    final stopwatch = Stopwatch()..start();
    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request));
    } on Exception catch (error) {
      _log.warning(
        'http_request_failed $method ${uri.path} '
        'correlation_id=$correlationId error=${error.runtimeType}',
      );
      throw ApiException.network(error, correlationId: correlationId);
    }

    final serverCorrelationId =
        response.headers['x-correlation-id'] ?? correlationId;
    _log.fine(
      'http_request $method ${uri.path} status=${response.statusCode} '
      'duration_ms=${stopwatch.elapsedMilliseconds} '
      'correlation_id=$serverCorrelationId',
    );

    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) _tokens.clear();
      throw ApiException.fromResponse(
        response.statusCode,
        decoded,
        correlationId: serverCorrelationId,
      );
    }
    return ApiResponse(
      status: response.statusCode,
      body: decoded,
      headers: response.headers,
    );
  }

  static Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return response.body;
    }
  }

  static String _joinPath(String base, String path) {
    final left = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final right = path.startsWith('/') ? path : '/$path';
    return '$left$right';
  }
}
