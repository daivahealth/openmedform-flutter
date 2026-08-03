/// Response serialization — building an empty draft and pruning it.
///
/// Ported from `packages/form-core/src/serialization/response.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
library;

import '../schema/json_schema.dart';
import '../schema/pointer.dart';
import '../validation/validator.dart';

String? _firstType(JsonSchema schema) {
  final type = schema['type'];
  if (type is List) return type.isEmpty ? null : '${type.first}';
  return type is String ? type : null;
}

Object? _buildEmpty(
  JsonSchema? schema,
  JsonSchema root, {
  required bool applyDefaults,
}) {
  final resolved = derefSchema(schema, root);
  if (resolved == null) return null;

  if (applyDefaults && resolved.containsKey('default')) {
    return resolved['default'];
  }

  final properties = resolved['properties'];
  if (_firstType(resolved) == 'object' && properties is Map) {
    final out = <String, dynamic>{};
    for (final entry in properties.entries) {
      final propertySchema = entry.value;
      final value = _buildEmpty(
        propertySchema is Map<String, dynamic> ? propertySchema : null,
        root,
        applyDefaults: applyDefaults,
      );
      if (value != null) out['${entry.key}'] = value;
    }
    return out;
  }

  // Leaves with no default stay absent. Object nesting is what a fresh draft
  // needs; placeholder scalars would defeat `required` validation.
  return null;
}

/// Build the empty draft response for a data schema.
Map<String, dynamic> createEmptyResponse(
  JsonSchema dataSchema, {
  bool applyDefaults = true,
}) {
  final result =
      _buildEmpty(dataSchema, dataSchema, applyDefaults: applyDefaults);
  return result is Map<String, dynamic> ? result : <String, dynamic>{};
}

bool _isEmptyLeaf(Object? value) => value == null || value == '';

/// Recursively remove empty leaves and empty objects.
///
/// Arrays are pruned element-wise but never dropped, because an empty array can
/// itself be meaningful. Booleans, zero and other falsy-but-real values are
/// preserved — dropping `false` or `0` would silently discard a clinical
/// answer.
Object? pruneEmptyValues(Object? data) {
  if (data is List) {
    return data.map(pruneEmptyValues).toList();
  }

  if (data is Map) {
    final out = <String, dynamic>{};
    for (final entry in data.entries) {
      final pruned = pruneEmptyValues(entry.value);
      if (_isEmptyLeaf(pruned)) continue;
      if (pruned is Map && pruned.isEmpty) continue;
      out['${entry.key}'] = pruned;
    }
    return out;
  }

  return data;
}

/// The outcome of preparing a response for submission.
class SubmitSerialization {
  const SubmitSerialization({
    required this.valid,
    required this.errors,
    required this.response,
  });

  final bool valid;
  final List<ValidationError> errors;

  /// The pruned payload actually submitted.
  final Map<String, dynamic> response;
}

/// Prepare a response for submission: prune, then validate against the data
/// schema.
///
/// The verdict is advisory. The server re-validates on
/// `POST /api/submissions/:id/complete` and its answer is the one that counts;
/// this exists so a client can stop an obviously invalid submit before making
/// the round trip.
SubmitSerialization serializeForSubmit(
  JsonSchema dataSchema,
  Map<String, dynamic> data,
  OmfValidator validator, {
  bool prune = true,
}) {
  final pruned = prune ? pruneEmptyValues(data) : data;
  final response =
      pruned is Map<String, dynamic> ? pruned : <String, dynamic>{};

  final result = validator.validate(dataSchema, response);
  return SubmitSerialization(
    valid: result.valid,
    errors: result.errors,
    response: response,
  );
}
