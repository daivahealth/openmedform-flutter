/// The default control registry.
///
/// Ranks come straight from `form-core`'s tester factories and are part of the
/// contract, not tuning knobs: a clinical control must outrank the generic
/// control that would otherwise claim the same element. Registration order
/// matters only among equal ranks, where the first entry wins.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../controls/standard_controls.dart';
import '../layouts/layouts.dart';
import 'render_context.dart';

/// Build the registry every form starts with.
///
/// A host may register additional entries to add or override controls — the
/// same extension story as the React and Angular renderers.
ControlRegistry<OmfWidgetBuilder> createDefaultRegistry() {
  final registry = ControlRegistry<OmfWidgetBuilder>();

  // --- layouts (rank 5) ----------------------------------------------------
  registry
    ..register(byType('VerticalLayout'), buildVerticalLayout)
    ..register(
      byType('HorizontalLayout'),
      (context) => OmfHorizontalLayout(context: context),
    )
    ..register(byType('Group'), (context) => OmfGroupLayout(context: context))
    ..register(byType('Label'), buildLabelElement);

  // --- controls by resolved schema type (rank 8) ---------------------------
  //
  // `date` is checked before the general string control by registering it at a
  // higher rank, since both match a string field.
  registry
    ..register(_dateTester, (context) => OmfDateControl(context: context))
    ..register(_enumTester, (context) => OmfEnumControl(context: context))
    ..register(
      bySchemaType('boolean'),
      (context) => OmfBooleanControl(context: context),
    )
    ..register(
      bySchemaType('integer'),
      (context) => OmfNumberControl(context: context, integer: true),
    )
    ..register(
      bySchemaType('number'),
      (context) => OmfNumberControl(context: context, integer: false),
    )
    ..register(
      bySchemaType('string'),
      (context) => OmfTextControl(context: context),
    );

  return registry;
}

/// A string field carrying `format: date`.
///
/// Rank 9 so it beats the plain string control, which also matches.
int _dateTester(Map<String, dynamic> element, ControlContext? context) {
  if (element['type'] != 'Control') return notApplicable;
  final schema = context?.fieldSchema;
  if (schema == null || !schema.hasType('string')) return notApplicable;
  return schema['format'] == 'date' ? 9 : notApplicable;
}

/// A field constrained by `enum`, whatever its type.
///
/// Rank 10 so it beats both the string control and the date control — an
/// enumerated field is a choice, not free text.
int _enumTester(Map<String, dynamic> element, ControlContext? context) {
  if (element['type'] != 'Control') return notApplicable;
  final schema = context?.fieldSchema;
  if (schema == null) return notApplicable;
  return schema.enumValues != null ? 10 : notApplicable;
}
