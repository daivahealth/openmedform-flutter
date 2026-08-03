/// JSON Pointer / JSON Forms scope resolution against a Data Schema.
///
/// Ported from `packages/form-core/src/schema/pointer.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// Two related-but-distinct paths are involved and must not be confused:
///
/// - A **schema path** (a JSON Forms "scope") walks the Data Schema structure
///   and therefore includes the `properties`/`items`/`$defs` keyword segments,
///   e.g. `#/properties/callDetails/properties/date`.
/// - A **data path** addresses a value inside a response object and contains
///   only property names, e.g. `callDetails.date`.
///
/// The scope → data path mapping follows JSON Forms' own convention — keep
/// every other segment, dropping the keyword segments — so bindings match the
/// React and Angular renderers exactly.
library;

import 'json_schema.dart';

/// Decode a single JSON Pointer segment (`~1` → `/`, `~0` → `~`).
///
/// Order matters and is not arbitrary: decoding `~0` first would turn `~01`
/// into `~1` and then into `/`, when it must decode to the literal `~1`.
String decodePointerSegment(String segment) =>
    segment.replaceAll('~1', '/').replaceAll('~0', '~');

/// Split a scope into its schema-path segments, dropping the leading `#`.
///
/// `#/properties/a/properties/b` → `['properties', 'a', 'properties', 'b']`;
/// `#/$defs/yesNo` → `[r'$defs', 'yesNo']`.
List<String> scopeToSchemaSegments(String scope) {
  final body = scope.startsWith('#') ? scope.substring(1) : scope;
  return body
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(decodePointerSegment)
      .toList();
}

/// Convert a scope into the data-path property names it addresses.
///
/// Keeps every other segment starting at index 1, dropping the keyword
/// segments: `#/properties/assessment/properties/spo2` →
/// `['assessment', 'spo2']`.
List<String> scopeToDataPathSegments(String scope) {
  final segments = scopeToSchemaSegments(scope);
  final out = <String>[];
  for (var i = 1; i < segments.length; i += 2) {
    out.add(segments[i]);
  }
  return out;
}

/// Dotted data path for a scope, e.g. `assessment.spo2`.
String scopeToDataPath(String scope) =>
    scopeToDataPathSegments(scope).join('.');

/// Walk raw schema segments without dereferencing — used to resolve a `$ref`.
Object? _walkSegments(JsonSchema root, List<String> segments) {
  Object? current = root;
  for (final segment in segments) {
    if (current is! Map<String, dynamic>) return null;
    current = current[segment];
  }
  return current;
}

/// Resolve a local `$ref` (e.g. `#/$defs/yesNo`) against the root schema.
///
/// Only same-document references are supported; an external ref resolves to
/// null rather than triggering a fetch.
JsonSchema? resolveRef(JsonSchema root, String ref) {
  if (!ref.startsWith('#')) return null;
  final resolved = _walkSegments(root, scopeToSchemaSegments(ref));
  return resolved is Map<String, dynamic> ? resolved : null;
}

/// Dereference a node one level if it is a `$ref`; otherwise return it as-is.
Object? _deref(Object? node, JsonSchema root) {
  if (node is Map<String, dynamic>) {
    final ref = node[r'$ref'];
    if (ref is String) return resolveRef(root, ref);
  }
  return node;
}

/// Dereference a schema node one level if it is a `$ref`.
JsonSchema? derefSchema(JsonSchema? schema, JsonSchema root) {
  final resolved = _deref(schema, root);
  return resolved is Map<String, dynamic> ? resolved : null;
}

/// Resolve the sub-schema a scope points at, dereferencing `$ref` nodes met
/// along the way and at the target. Returns null when the scope does not
/// resolve.
JsonSchema? resolveSchemaAtScope(JsonSchema root, String scope) {
  final segments = scopeToSchemaSegments(scope);
  Object? current = root;

  for (final segment in segments) {
    current = _deref(current, root);
    if (current is! Map<String, dynamic>) return null;
    current = current[segment];
  }

  final resolved = _deref(current, root);
  return resolved is Map<String, dynamic> ? resolved : null;
}
