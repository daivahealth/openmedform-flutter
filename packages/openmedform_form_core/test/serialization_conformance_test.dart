/// Replays the `serialization` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

import 'support/conformance.dart';

Map<String, dynamic> _map(Object? raw) =>
    Map<String, dynamic>.from(raw! as Map);

/// The portable part of a `serializeForSubmit` result.
///
/// The verdict and the pruned payload must match exactly. The error *objects*
/// must not be: the fixture holds Ajv's messages and `params`, which no Dart
/// validator reproduces. What is comparable is which paths were flagged, so
/// that is what this projects — the same contract enforced in
/// `validation_conformance_test.dart`.
Object? _portable(Object? value) {
  final result = _map(value);
  final flagged = (result['errors']! as List<Object?>)
      .map((error) => '${_map(error)['instancePath']}')
      .toSet()
      .toList()
    ..sort();

  return <String, dynamic>{
    'valid': result['valid'],
    'response': result['response'],
    'flaggedPaths': flagged,
  };
}

void main() {
  runConformanceModule(
    'serialization',
    {
      'createEmptyResponse': (args) {
        final options = args.length > 1 && args[1] != null
            ? _map(args[1])
            : const <String, dynamic>{};
        return createEmptyResponse(
          _map(args[0]),
          applyDefaults: options['applyDefaults'] as bool? ?? true,
        );
      },
      'pruneEmptyValues': (args) => pruneEmptyValues(args[0]),
      'serializeForSubmit': (args) {
        final result = serializeForSubmit(
          _map(args[0]),
          _map(args[1]),
          JsonSchemaValidator(),
        );
        return <String, dynamic>{
          'valid': result.valid,
          'errors': result.errors.map((error) => error.toJson()).toList(),
          'response': result.response,
        };
      },
    },
    project: {'serializeForSubmit': _portable},
  );
}
