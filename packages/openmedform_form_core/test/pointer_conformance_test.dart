/// Replays the `pointer` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

import 'support/conformance.dart';

void main() {
  runConformanceModule('pointer', {
    'decodePointerSegment': (args) => decodePointerSegment(args[0]! as String),
    'scopeToSchemaSegments': (args) =>
        scopeToSchemaSegments(args[0]! as String),
    'scopeToDataPathSegments': (args) =>
        scopeToDataPathSegments(args[0]! as String),
    'scopeToDataPath': (args) => scopeToDataPath(args[0]! as String),
    'resolveSchemaAtScope': (args) => resolveSchemaAtScope(
          args[0]! as JsonSchema,
          args[1]! as String,
        ),
    'resolveRef': (args) => resolveRef(
          args[0]! as JsonSchema,
          args[1]! as String,
        ),
    // Note the argument order: the node to dereference comes first, the root
    // second.
    'derefSchema': (args) => derefSchema(
          args[0] as JsonSchema?,
          args[1]! as JsonSchema,
        ),
  });
}
