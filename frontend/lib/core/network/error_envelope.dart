class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const {},
    this.requestId,
    this.retryable = false,
    this.retryAfter,
    this.lockedUntil,
  });

  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic> details;
  final String? requestId;
  final bool retryable;
  final int? retryAfter;
  final DateTime? lockedUntil;

  bool get isLockout => code == 'ACCOUNT_LOCKED';
  bool get isAuth => code == 'AUTH';

  factory ApiException.fromBody(int status, Map<String, dynamic> body, {int? retryAfter}) {
    final err = (body['error'] as Map?)?.cast<String, dynamic>() ?? {};
    final details = (err['details'] as Map?)?.cast<String, dynamic>() ?? {};
    DateTime? locked;
    final raw = details['locked_until'];
    if (raw is String) {
      locked = DateTime.tryParse(raw)?.toLocal();
    }
    return ApiException(
      statusCode: status,
      code: (err['code'] as String?) ?? 'INTERNAL',
      message: (err['message'] as String?) ?? 'Request failed',
      details: details,
      requestId: err['request_id'] as String?,
      retryable: err['retryable'] as bool? ?? false,
      retryAfter: retryAfter,
      lockedUntil: locked,
    );
  }

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}
