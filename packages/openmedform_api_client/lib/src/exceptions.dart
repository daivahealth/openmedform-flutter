/// Errors the API returns, in a shape a form UI can act on.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

/// Anything the API rejected.
class OmfApiException implements Exception {
  const OmfApiException({
    required this.message,
    this.statusCode,
    this.body,
  });

  final String message;
  final int? statusCode;
  final Object? body;

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'OmfApiException($statusCode): $message';
}

/// A 400 from `POST /api/submissions/:id/complete`.
///
/// The server re-validates with Ajv and its verdict is the authoritative one.
/// The errors carry JSON Pointers, so a client can map them straight back onto
/// the fields that produced them.
class OmfValidationException extends OmfApiException {
  const OmfValidationException({
    required super.message,
    required this.errors,
    super.statusCode = 400,
    super.body,
  });

  /// Parse the `{message, errors: [...]}` payload the API returns.
  factory OmfValidationException.fromBody(Map<String, dynamic> body) {
    final rawErrors = body['errors'];
    final errors = rawErrors is List
        ? rawErrors
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (error) => ValidationError(
                instancePath: '${error['instancePath'] ?? ''}',
                keyword: '${error['keyword'] ?? 'unknown'}',
                message: '${error['message'] ?? ''}',
                params: error['params'] is Map
                    ? Map<String, dynamic>.from(error['params'] as Map)
                    : const <String, dynamic>{},
              ),
            )
            .toList()
        : const <ValidationError>[];

    return OmfValidationException(
      message: '${body['message'] ?? 'Submission failed validation'}',
      errors: errors,
      body: body,
    );
  }

  final List<ValidationError> errors;

  /// Whether the payload looks like the server's validation-failure shape.
  static bool looksLikeValidationFailure(Object? body) =>
      body is Map && body['errors'] is List;

  /// Group the errors by the field they refer to, for highlighting.
  Map<String, List<ValidationError>> get byInstancePath {
    final grouped = <String, List<ValidationError>>{};
    for (final error in errors) {
      grouped.putIfAbsent(error.instancePath, () => <ValidationError>[]).add(error);
    }
    return grouped;
  }
}
