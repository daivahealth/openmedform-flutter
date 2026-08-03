/// Replays the `i18n` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

import 'support/conformance.dart';

TranslationBundle _bundle(Object? raw) =>
    TranslationBundle.fromJson(Map<String, dynamic>.from(raw! as Map));

void main() {
  runConformanceModule('i18n', {
    'resolveTranslation': (args) => resolveTranslation(
          _bundle(args[0]),
          args[1]! as String,
          args[2]! as String,
          args.length > 3 ? args[3] as String? : null,
        ),
    'hasLanguage': (args) => hasLanguage(_bundle(args[0]), args[1]! as String),
  });
}
