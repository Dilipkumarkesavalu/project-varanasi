/// One field error from a `422` response (ADR-0007 §5).
class FieldError {
  const FieldError({
    required this.field,
    required this.code,
    required this.message,
  });

  final String field;
  final String code;
  final String message;
}

/// An API error parsed from an RFC 9457 Problem Details body (ADR-0007 §5).
///
/// Branch on [code], never on [title] or [detail].
class ApiException implements Exception {
  const ApiException({
    required this.status,
    required this.code,
    required this.title,
    this.detail,
    this.correlationId,
    this.fieldErrors = const [],
  });

  /// Builds an exception from a decoded response body, tolerating non-Problem bodies.
  factory ApiException.fromResponse(
    int status,
    Object? body, {
    String? correlationId,
  }) {
    final json = body is Map<String, Object?>
        ? body
        : const <String, Object?>{};
    final errors = json['errors'];
    return ApiException(
      status: status,
      code: json['code'] as String? ?? _fallbackCode(status),
      title: json['title'] as String? ?? 'Request failed',
      detail: json['detail'] as String?,
      correlationId: json['correlation_id'] as String? ?? correlationId,
      fieldErrors: errors is List
          ? [
              for (final item in errors.whereType<Map<String, Object?>>())
                FieldError(
                  field: item['field'] as String? ?? '',
                  code: item['code'] as String? ?? '',
                  message: item['message'] as String? ?? '',
                ),
            ]
          : const [],
    );
  }

  /// Network failure: the request never got a response.
  factory ApiException.network(Object error, {String? correlationId}) =>
      ApiException(
        status: 0,
        code: 'network_error',
        title: 'Could not reach the server',
        detail: error.toString(),
        correlationId: correlationId,
      );

  final int status;
  final String code;
  final String title;
  final String? detail;
  final String? correlationId;
  final List<FieldError> fieldErrors;

  bool get isUnauthenticated => status == 401;
  bool get isNotFound => status == 404;
  bool get isValidation => status == 422;

  static String _fallbackCode(int status) => switch (status) {
    400 => 'bad_request',
    401 => 'unauthenticated',
    403 => 'permission_denied',
    404 => 'not_found',
    409 => 'conflict',
    412 => 'version_mismatch',
    422 => 'validation_failed',
    429 => 'rate_limited',
    _ => 'internal_error',
  };

  @override
  String toString() =>
      'ApiException($status $code: $title, correlation_id=$correlationId)';
}
