/// Data validation against a JSON Schema 2020-12 data schema.
///
/// Adapted from `packages/form-core/src/validation/validate-data.ts` at
/// form-core 32236d66e350f89d6c76f120007a705963fa3312. This is the one module
/// that is an adaptation rather than a transliteration: upstream uses Ajv,
/// which has no Dart equivalent.
///
/// The abstraction exists so the underlying package is swappable. The error
/// shape deliberately matches both form-core's `ValidationError` and the API's
/// 400 payload, so code that renders errors does not care whether they came
/// from here or from the server.
///
/// **Local validation is advisory.** `POST /api/submissions/:id/complete`
/// re-validates with Ajv and recalculates every score server-side. The job here
/// is to help a clinician fix problems before submitting, not to decide whether
/// a submission is valid.
library;

import '../schema/json_schema.dart';

/// A single validation failure.
class ValidationError {
  const ValidationError({
    required this.instancePath,
    required this.keyword,
    required this.message,
    this.params = const <String, dynamic>{},
  });

  /// JSON Pointer to the offending value, e.g. `/assessment/spo2`.
  ///
  /// The empty string means the root instance.
  final String instancePath;

  /// The schema keyword that failed, e.g. `required`, `maximum`, `type`.
  ///
  /// Best-effort: the Dart validator does not report a keyword directly, so
  /// this is recovered from its diagnostics. Treat it as a hint for choosing a
  /// friendly message, not as a contract. See docs/CONFORMANCE.md.
  final String keyword;

  final String message;

  final Map<String, dynamic> params;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'instancePath': instancePath,
        'keyword': keyword,
        'message': message,
        'params': params,
      };

  @override
  String toString() =>
      '${instancePath.isEmpty ? '(root)' : instancePath}: $message [$keyword]';
}

class ValidationResult {
  const ValidationResult({required this.valid, required this.errors});

  const ValidationResult.ok()
      : valid = true,
        errors = const <ValidationError>[];

  final bool valid;
  final List<ValidationError> errors;

  /// Errors affecting a particular data path, for field-level display.
  Iterable<ValidationError> errorsAt(String instancePath) =>
      errors.where((error) => error.instancePath == instancePath);
}

/// Validates data against a JSON Schema.
///
/// Implementations must be safe to call on every rebuild: rule evaluation runs
/// through here for each element that carries a condition schema.
abstract class OmfValidator {
  const OmfValidator();

  ValidationResult validate(JsonSchema schema, Object? data);
}
