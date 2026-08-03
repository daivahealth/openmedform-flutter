/// Replays the `serialization` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

import 'support/conformance.dart';

Map<String, dynamic> _map(Object? raw) =>
    Map<String, dynamic>.from(raw! as Map);

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
    },
    pending: const {
      'serializeForSubmit': 'validates against the data schema, so it lands '
          'with the validator in M2 (#3)',
    },
  );
}
