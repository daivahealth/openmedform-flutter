/// Choice controls: `enum`, labelled `oneOf`, and array-valued checkbox groups.
///
/// The platform emits three different shapes for "pick from a list", and two of
/// them used to render as unsupported-element placeholders here while working
/// on the web. Both were found by rendering a real published form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

Map<String, dynamic> _control(String property, [Map<String, dynamic>? omf]) =>
    <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/$property',
      if (omf != null) 'options': <String, dynamic>{'omf': omf},
    };

Map<String, dynamic> _layout(List<Map<String, dynamic>> elements) =>
    <String, dynamic>{'type': 'VerticalLayout', 'elements': elements};

void main() {
  group('labelled oneOf', () {
    // The generator emits this whenever display text differs from the stored
    // code. It carries no `type`, so nothing matched it before and the whole
    // field rendered as a red placeholder.
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'bodyHabitus': <String, dynamic>{
          'title': 'Body Habitus',
          'oneOf': <dynamic>[
            <String, dynamic>{'const': 'CACHETIC', 'title': 'Cachectic'},
            <String, dynamic>{
              'const': 'AVERAGE_BUILT',
              'title': 'Average built'
            },
          ],
        },
      },
    };

    testWidgets('renders as a picker rather than an unsupported element',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('bodyHabitus')]),
        ),
      );

      expect(find.byType(UnknownElementWidget), findsNothing);
      expect(find.byType(DropdownButtonFormField<Object?>), findsOneWidget);
    });

    testWidgets('shows the title and stores the const', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('bodyHabitus')]),
        ),
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(DropdownButtonFormField<Object?>));
      await tester.pumpAndSettle();

      // A clinician must never be shown the storage code.
      expect(find.text('Average built'), findsWidgets);
      expect(find.text('AVERAGE_BUILT'), findsNothing);

      await tester.tap(find.text('Average built').last);
      await tester.pumpAndSettle();

      expect(seen?['bodyHabitus'], 'AVERAGE_BUILT');
    });

    testWidgets('works as a radio too', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[
            _control('bodyHabitus', <String, dynamic>{'control': 'radio'}),
          ]),
        ),
        onChange: (data) => seen = data,
      );

      expect(find.text('Cachectic'), findsOneWidget);

      await tester.tap(find.text('Cachectic'));
      await tester.pump();

      expect(seen?['bodyHabitus'], 'CACHETIC');
    });

    testWidgets('a combinator that is not a plain choice is left alone',
        (tester) async {
      // `oneOf` is also a validation construct. Only branches that are all
      // labelled constants describe a picker.
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'value': <String, dynamic>{
                'title': 'Value',
                'oneOf': <dynamic>[
                  <String, dynamic>{'type': 'string', 'maxLength': 3},
                  <String, dynamic>{'type': 'number'},
                ],
              },
            },
          },
          layout: _layout(<Map<String, dynamic>>[_control('value')]),
        ),
      );

      expect(find.byType(DropdownButtonFormField<Object?>), findsNothing);
    });
  });

  group('array-valued checkbox group', () {
    // One Control for a whole group, value an array of codes. JSON Forms calls
    // this a multi-enum and its vanilla renderers handle it, which is why such
    // a form renders on the web.
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'valuables': <String, dynamic>{
          'type': 'array',
          'title': 'Valuables',
          'items': <String, dynamic>{
            'type': 'string',
            'enum': <String>['Dentures', 'Hearing aid', 'Dress'],
          },
        },
      },
    };

    testWidgets('renders one checkbox per option', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('valuables')]),
        ),
      );

      expect(find.byType(UnknownElementWidget), findsNothing);
      expect(tester.widgetList(find.byType(Checkbox)), hasLength(3));
      expect(find.text('Hearing aid'), findsOneWidget);
    });

    testWidgets('stores the codes in schema order, not tick order',
        (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('valuables')]),
        ),
        onChange: (data) => seen = data,
      );

      // Ticked back to front on purpose: tick order would store
      // ['Dress', 'Dentures'].
      await tester.tap(find.text('Dress'));
      await tester.pump();
      await tester.tap(find.text('Dentures'));
      await tester.pump();

      // Both web renderers serialize these in the order the schema declares
      // them, and ADR-003 makes identical value derivation a safety
      // requirement — the same boxes must produce the same stored answer
      // whichever order a clinician happened to tap them in.
      expect(seen?['valuables'], <String>['Dentures', 'Dress']);
    });

    testWidgets('unticking removes just that code', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('valuables')]),
        ),
        initialData: const <String, dynamic>{
          'valuables': <String>['Dentures', 'Dress'],
        },
        onChange: (data) => seen = data,
      );

      await tester.tap(find.text('Dentures'));
      await tester.pump();

      expect(seen?['valuables'], <String>['Dress']);
    });

    testWidgets('emptying the group removes the property', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('valuables')]),
        ),
        initialData: const <String, dynamic>{
          'valuables': <String>['Dress'],
        },
        onChange: (data) => seen = data,
      );

      await tester.tap(find.text('Dress'));
      await tester.pump();

      // Same reasoning as a cleared text field: `required` checks key presence,
      // so an empty array and an absent key are different verdicts.
      expect(seen?.containsKey('valuables'), isFalse);
    });

    testWidgets('initial selection is reflected', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layout(<Map<String, dynamic>>[_control('valuables')]),
        ),
        initialData: const <String, dynamic>{
          'valuables': <String>['Dentures'],
        },
      );

      final checked = tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .where((box) => box.value == true);
      expect(checked, hasLength(1));
    });

    testWidgets('labelled oneOf items work too', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'allergyTypes': <String, dynamic>{
                'type': 'array',
                'title': 'Allergy Type',
                'items': <String, dynamic>{
                  'oneOf': <dynamic>[
                    <String, dynamic>{'const': 'DRUGS', 'title': 'Drugs'},
                    <String, dynamic>{
                      'const': 'FOOD_AND_BEVERAGES',
                      'title': 'Food and beverages',
                    },
                  ],
                },
              },
            },
          },
          layout: _layout(<Map<String, dynamic>>[_control('allergyTypes')]),
        ),
        onChange: (data) => seen = data,
      );

      expect(find.text('Food and beverages'), findsOneWidget);

      await tester.tap(find.text('Food and beverages'));
      await tester.pump();

      expect(seen?['allergyTypes'], <String>['FOOD_AND_BEVERAGES']);
    });

    testWidgets('an array of objects is still a record table', (tester) async {
      // The record table's safety net outranks this control, so a repeating
      // log does not degrade into a list of checkboxes.
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'rounds': <String, dynamic>{
                'type': 'array',
                'title': 'Round',
                'items': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'nurse': <String, dynamic>{'type': 'string'},
                  },
                },
              },
            },
          },
          layout: _layout(<Map<String, dynamic>>[_control('rounds')]),
        ),
      );

      expect(find.byType(OmfRecordTable), findsOneWidget);
    });
  });
  group('checkboxGroup dispatch', () {
    // A flat row of "tick all that apply" options. The converter used to label
    // these `checklistMatrix` — the F273 Internal Patient Transfer form's
    // measure_type / suspected / bloodborne fields are all this shape.
    const enumArray = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'measureType': <String, dynamic>{
          'type': 'array',
          'title': 'Measure type',
          'items': <String, dynamic>{
            'type': 'string',
            'enum': <String>['Contact', 'Droplet', 'Airborne'],
          },
        },
      },
    };

    testWidgets('claims an element named checkboxGroup', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: enumArray,
          layout: _layout(<Map<String, dynamic>>[
            _control('measureType', <String, dynamic>{
              'control': 'checkboxGroup',
            }),
          ]),
        ),
      );

      expect(find.byType(OmfMultiEnumControl), findsOneWidget);
      expect(find.byType(UnknownElementWidget), findsNothing);
    });

    testWidgets('rescues an enum-array mislabelled checklistMatrix',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: enumArray,
          layout: _layout(<Map<String, dynamic>>[
            _control('measureType', <String, dynamic>{
              'control': 'checklistMatrix',
            }),
          ]),
        ),
      );

      // Before this outranked the matrix the element reached
      // OmfChecklistMatrix, which looks for omf.rows/omf.columns, found
      // neither, and drew an empty grid — the options were simply gone.
      expect(find.byType(OmfChecklistMatrix), findsNothing);
      expect(find.byType(OmfMultiEnumControl), findsOneWidget);
      expect(tester.widgetList(find.byType(Checkbox)), hasLength(3));
      expect(find.text('Droplet'), findsOneWidget);
    });

    testWidgets('leaves a configured checklistMatrix alone', (tester) async {
      // The real thing binds an object property and carries its own grid, so
      // it has no array items and cannot be claimed by shape.
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'rounds': <String, dynamic>{'type': 'object', 'title': 'Rounds'},
            },
          },
          layout: _layout(<Map<String, dynamic>>[
            _control('rounds', <String, dynamic>{
              'control': 'checklistMatrix',
              'rows': <dynamic>[
                <String, dynamic>{'key': 'mouth', 'label': 'Mouth care'},
              ],
              'columns': <dynamic>[
                <String, dynamic>{'key': 'd1', 'label': 'Day 1'},
              ],
            }),
          ]),
        ),
      );

      expect(find.byType(OmfChecklistMatrix), findsOneWidget);
      expect(find.byType(OmfMultiEnumControl), findsNothing);
    });
  });
}
