/// The default control registry.
///
/// Ranks come straight from `form-core`'s tester factories and are part of the
/// contract, not tuning knobs: a clinical control must outrank the generic
/// control that would otherwise claim the same element. Registration order
/// matters only among equal ranks, where the first entry wins.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../clinical/clinical_controls.dart';
import '../clinical/matrices.dart';
import '../clinical/record_table.dart';
import '../clinical/score_summary.dart';
import '../controls/multi_enum_control.dart';
import '../controls/standard_controls.dart';
import '../layouts/layouts.dart';
import '../layouts/omf_layouts.dart';
import 'render_context.dart';

/// Build the registry every form starts with.
///
/// A host may register additional entries to add or override controls — the
/// same extension story as the React and Angular renderers.
ControlRegistry<OmfWidgetBuilder> createDefaultRegistry() {
  final registry = ControlRegistry<OmfWidgetBuilder>();

  // --- multi-select checkbox group (rank 21) -------------------------------
  //
  // Sits above every other omf control. See _checkboxGroupTester for why that
  // one rank matters.
  registry.register(
    _checkboxGroupTester,
    (context) => OmfMultiEnumControl(context: context),
  );

  // --- clinical controls (rank 20) -----------------------------------------
  //
  // Highest rank: a clinical control must outrank the generic control that
  // would otherwise claim the same element by schema type.
  registry
    ..register(
      byOmfControl('textarea'),
      (context) => OmfTextControl(context: context, multiline: true),
    )
    ..register(byOmfControl('radio'), (c) => OmfRadioControl(context: c))
    ..register(
      byOmfControl('signatureDate'),
      (c) => OmfSignatureDateControl(context: c),
    )
    ..register(
      byOmfControl('riskStratification'),
      (c) => OmfRiskStratificationControl(context: c),
    )
    ..register(
      byOmfControl('vitalSignsChart'),
      (c) => OmfVitalSignsChart(context: c),
    )
    ..register(
      byOmfControl('colorCodedGrid'),
      (c) => OmfColorCodedGrid(context: c),
    )
    ..register(
      byOmfControl('clinicalReferenceTable'),
      (c) => OmfClinicalReferenceTable(context: c),
    )
    ..register(
        byOmfControl('scoringMatrix'), (c) => OmfScoringMatrix(context: c))
    ..register(
      byOmfControl('checklistMatrix'),
      (c) => OmfChecklistMatrix(context: c),
    )
    ..register(byOmfControl('scoreSummary'), (c) => OmfScoreSummary(context: c))
    // Also claims any unconfigured array-of-objects — see recordTableTester.
    ..register(recordTableTester, (c) => OmfRecordTable(context: c));

  // --- custom layouts (rank 15) --------------------------------------------
  registry
    ..register(byOmfLayout('OmfTableLayout'), (c) => OmfTableLayout(context: c))
    ..register(byOmfLayout('OmfTabsLayout'), (c) => OmfTabsLayout(context: c))
    // Categorization has no custom renderer upstream: React falls through to
    // JSON Forms' vanilla tabs and Angular renders nothing. Tabs match what a
    // clinician actually sees on the web, so that is what is reproduced here.
    // Recorded in docs/PARITY.md as a deliberate difference from Angular.
    ..register(byOmfLayout('Categorization'), (c) => OmfTabsLayout(context: c))
    ..register(byOmfLayout('Category'), buildVerticalLayout);

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
    ..register(
      _byStringFormat('date'),
      (context) => OmfDateControl(context: context),
    )
    ..register(
      _byStringFormat('time'),
      (context) => OmfTimeControl(context: context),
    )
    ..register(
      _byStringFormat('date-time'),
      (context) => OmfDateTimeControl(context: context),
    )
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

/// A string field carrying a given `format`.
///
/// Rank 9 so it beats the plain string control, which also matches. `date`,
/// `time` and `date-time` each get their own picker; every other format
/// (`email` among them) stays on the text control, which reads the format
/// itself to choose a keyboard.
ControlTester _byStringFormat(String format) => (element, context) {
      if (element['type'] != 'Control') return notApplicable;
      final schema = context?.fieldSchema;
      if (schema == null || !schema.hasType('string')) return notApplicable;
      return schema['format'] == format ? 9 : notApplicable;
    };

/// A field constrained to a set of choices, whatever its type.
///
/// Covers `enum` and the labelled `oneOf`/`anyOf` form the generator emits when
/// display text differs from the stored code. Rank 10 so it beats both the
/// string control and the date control — an enumerated field is a choice, not
/// free text.
int _enumTester(Map<String, dynamic> element, ControlContext? context) {
  if (element['type'] != 'Control') return notApplicable;
  final schema = context?.fieldSchema;
  if (schema == null) return notApplicable;
  return schema.options != null ? 10 : notApplicable;
}

/// One above every other omf control (which register at 20).
const int _checkboxGroupRank = 21;

/// The multi-select checkbox group: an explicit `omf.control: "checkboxGroup"`,
/// or any array whose items are `enum`/`oneOf` codes — whatever control name it
/// wears.
///
/// Claiming the shape rather than trusting the label is the point of that extra
/// rank. The converter used to emit `checklistMatrix` for these flat option rows
/// (the F273 transfer form's `measure_type`, `suspected`, `bloodborne`), and
/// that name registers at 20 — so a mislabelled element reached the rows x
/// columns matrix, found no `omf.rows`/`omf.columns` to lay out, and drew an
/// empty grid. Both web renderers rescue it the same way, at the same rank.
///
/// A configured checklistMatrix is never stolen. It binds an object property
/// holding a nested `{row: {column: true}}` value, so it has no array items and
/// therefore no [JsonSchema.itemOptions]. The record table's array-of-objects
/// safety net survives for the same reason: object items carry no options.
int _checkboxGroupTester(
    Map<String, dynamic> element, ControlContext? context) {
  if (element['type'] != 'Control') return notApplicable;
  if (omfControl(element) == 'checkboxGroup') return _checkboxGroupRank;
  return context?.fieldSchema?.itemOptions != null
      ? _checkboxGroupRank
      : notApplicable;
}
