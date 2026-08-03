/// The default [OmfValidator], backed by `package:json_schema`.
///
/// Chosen in M2 (#3) after being measured against the validation conformance
/// suite generated from Ajv. Results on that suite, with the divergences
/// written up in CONFORMANCE.md:
///
/// - `valid` matches Ajv on every case.
/// - Every instance path Ajv reports is also reported here.
/// - Extra, more specific paths appear for `required` — Ajv points at the
///   containing object, this also points at the missing property. That is
///   better for field highlighting, not a defect.
/// - The failing keyword is recovered from diagnostics rather than read from a
///   field, because the package does not expose one.
library;

import 'package:json_schema/json_schema.dart' as js;

import '../schema/json_schema.dart';
import 'validator.dart';

/// Maps a diagnostic message fragment to the keyword it implies.
///
/// Ordered longest-context-first where fragments could overlap. This is the
/// fragile part of the adapter — a package upgrade can reword a message — so
/// the dependency is pinned and [_keywordFrom] degrades to the schema path
/// rather than throwing.
const Map<String, String> _messageKeywords = <String, String>{
  'required prop missing': 'required',
  'type: wanted': 'type',
  'enum violated': 'enum',
  'const violated': 'const',
  'maximum exceeded': 'maximum',
  'minimum violated': 'minimum',
  'exclusiveMaximum exceeded': 'exclusiveMaximum',
  'exclusiveMinimum violated': 'exclusiveMinimum',
  'minLength violated': 'minLength',
  'maxLength violated': 'maxLength',
  'pattern violated': 'pattern',
  'multipleOf violated': 'multipleOf',
  'uniqueItems violated': 'uniqueItems',
  'minItems violated': 'minItems',
  'maxItems violated': 'maxItems',
  'allOf violated': 'allOf',
  'anyOf violated': 'anyOf',
  'oneOf violated': 'oneOf',
  'not violated': 'not',
  'unevaluatedProperties': 'unevaluatedProperties',
  'additionalProperties': 'additionalProperties',
  'additionalItems': 'additionalItems',
};

String _keywordFrom(String message, String schemaPath) {
  for (final entry in _messageKeywords.entries) {
    if (message.contains(entry.key)) return entry.value;
  }
  if (message.contains('format')) return 'format';

  // Fall back to the last schema-path segment. Often the property name rather
  // than a keyword, but better than an empty string when diagnosing.
  final segments = schemaPath
      .replaceAll(RegExp('^#'), '')
      .split('/')
      .where((segment) => segment.isNotEmpty);
  return segments.isEmpty ? 'unknown' : segments.last;
}

/// Validates with `package:json_schema` against draft 2020-12.
class JsonSchemaValidator extends OmfValidator {
  JsonSchemaValidator();

  /// Compiled-schema cache.
  ///
  /// Rules are evaluated on every rebuild, and compiling a schema per frame
  /// would be wasteful. An [Expando] keys off the schema map's identity and
  /// lets the entry be collected with the schema itself, so a form that is
  /// closed does not leak its compiled schemas.
  final Expando<js.JsonSchema> _compiled = Expando<js.JsonSchema>('omf.schema');

  js.JsonSchema? _compile(JsonSchema schema) {
    final cached = _compiled[schema];
    if (cached != null) return cached;

    try {
      final built = js.JsonSchema.create(
        schema,
        schemaVersion: js.SchemaVersion.draft2020_12,
      );
      _compiled[schema] = built;
      return built;
    } on Object {
      // An uncompilable schema is an authoring bug, not a data problem. Report
      // it as such rather than crashing a form the clinician is filling in.
      return null;
    }
  }

  @override
  ValidationResult validate(JsonSchema schema, Object? data) {
    final compiled = _compile(schema);
    if (compiled == null) {
      return const ValidationResult(
        valid: false,
        errors: <ValidationError>[
          ValidationError(
            instancePath: '',
            keyword: 'schema',
            message: 'The data schema could not be compiled.',
          ),
        ],
      );
    }

    // Formats are annotations by default in 2020-12; Ajv asserts them via
    // ajv-formats, so assert them here too or `format: date` would never fail.
    final result = compiled.validate(data, validateFormats: true);
    if (result.isValid) return const ValidationResult.ok();

    return ValidationResult(
      valid: false,
      errors: result.errors
          .map(
            (error) => ValidationError(
              instancePath: error.instancePath,
              keyword: _keywordFrom(error.message, error.schemaPath),
              message: error.message,
              params: <String, dynamic>{'schemaPath': error.schemaPath},
            ),
          )
          .toList(),
    );
  }
}

/// Whether a schema compiles at all.
///
/// Returns null on success, or a message describing why it failed. Useful when
/// loading a form definition, so an authoring error surfaces before a clinician
/// starts filling the form in.
String? checkSchemaCompiles(JsonSchema dataSchema) {
  try {
    js.JsonSchema.create(
      dataSchema,
      schemaVersion: js.SchemaVersion.draft2020_12,
    );
    return null;
  } on Object catch (error) {
    return error.toString();
  }
}
