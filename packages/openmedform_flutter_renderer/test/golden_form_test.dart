/// Renders the rrt-sbar reference form end to end.
///
/// This is the M3 exit criterion: the whole golden form builds, standard
/// elements render as real controls, and the clinical controls that land in M4
/// and M5 show as visible placeholders rather than vanishing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

void main() {
  testWidgets('the golden form renders without throwing', (tester) async {
    await pumpForm(tester, definition: goldenDefinition());

    expect(tester.takeException(), isNull);
    expect(find.byType(OmfFormRenderer), findsOneWidget);
  });

  testWidgets(
      'its Greek section titles come from the schema, not humanised '
      'English keys', (tester) async {
    await pumpForm(tester, definition: goldenDefinition());

    // The form is Greek and leans on `title` precisely so humanised English
    // never reaches a clinician. Seeing "Call Details" here would mean the
    // label chain fell through to the key.
    expect(find.textContaining('Ημ/νία'), findsWidgets);
    expect(find.textContaining('Call Details'), findsNothing);
    expect(find.textContaining('Floor Room'), findsNothing);
  });

  testWidgets('standard controls render as real inputs', (tester) async {
    await pumpForm(tester, definition: goldenDefinition());

    expect(find.byType(TextField), findsWidgets);
    expect(find.byType(Checkbox), findsWidgets);
  });

  testWidgets('every element in it is claimed by some control', (tester) async {
    await pumpForm(tester, definition: goldenDefinition());

    // No placeholders, which is a better outcome than M3 planned for. The
    // form's omf-specific controls degrade to their underlying type rather than
    // falling through: `textarea` is a string field, so the string control
    // claims it; `radio` is an enum, so the enum control does; and the dead
    // `pageColumns` marker sits on a HorizontalLayout that renders normally.
    //
    // The degradation is cosmetic, not semantic — a textarea rendered on one
    // line still writes the same string. M4 (#5) restores the right shapes.
    expect(find.byType(UnknownElementWidget), findsNothing);

    // All 23 controls accounted for: 14 text (three of them the multiline
    // `textarea`), 7 checkbox, 1 date, and the `radio` — which is now four
    // radio buttons rather than the dropdown it fell back to before M4.
    expect(tester.widgetList(find.byType(TextField)), hasLength(14));
    expect(tester.widgetList(find.byType(Checkbox)), hasLength(7));
    expect(tester.widgetList(find.byType(Radio<Object?>)), hasLength(4));
    expect(
      tester.widgetList(find.byType(DropdownButtonFormField<Object?>)),
      isEmpty,
    );
  });

  testWidgets('its textareas render multiline', (tester) async {
    await pumpForm(tester, definition: goldenDefinition());

    final multiline = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((field) => field.maxLines == null);

    // Three `omf.control: textarea` fields, which before M4 fell through to the
    // single-line string control.
    expect(multiline, hasLength(3));
  });

  testWidgets('a completed sample populates its fields', (tester) async {
    final sample = loadGolden('rrt-sbar.sample-completed.json');
    await pumpForm(
      tester,
      definition: goldenDefinition(),
      initialData: sample,
    );

    expect(tester.takeException(), isNull);

    // The sample records a date; it should be showing somewhere on screen.
    final date = (sample['callDetails'] as Map)['date'];
    expect(find.textContaining('$date'), findsWidgets);
  });

  testWidgets('read-only mode disables every input', (tester) async {
    await pumpForm(
      tester,
      definition: goldenDefinition(),
      initialData: loadGolden('rrt-sbar.sample-completed.json'),
      readOnly: true,
    );

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, isNotEmpty);
    for (final field in fields) {
      expect(field.enabled, isFalse);
    }

    for (final box in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
      expect(box.onChanged, isNull);
    }
  });
}
