/// Pure Dart port of `@openmedform/form-core`.
///
/// This library must never import the Flutter SDK — it is consumed by the
/// renderer, but is also usable from plain Dart (CLI tooling, server-side
/// checks, tests). CI enforces this; see `melos run check:purity`.
///
/// Ported from form-core `32236d66e350f89d6c76f120007a705963fa3312`. Each file
/// records the same pin; `CONFORMANCE.md` explains how to move it.
///
/// See ARCHITECTURE.md section 3 for the port table.
library;

export 'src/binding/data_path.dart';
export 'src/i18n/translate.dart';
export 'src/record_table/summary.dart';
export 'src/registry/control_registry.dart';
export 'src/rules/evaluate_rule.dart';
export 'src/schema/json_schema.dart';
export 'src/schema/labels.dart';
export 'src/schema/pointer.dart';
export 'src/scoring/score.dart';
export 'src/serialization/response.dart';
export 'src/ui/ui_element.dart';
export 'src/validation/json_schema_validator.dart';
export 'src/validation/validator.dart';
