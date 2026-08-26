/// The custom `Omf*` layouts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'systolic': <String, dynamic>{'type': 'integer', 'title': 'Systolic'},
    'diastolic': <String, dynamic>{'type': 'integer', 'title': 'Diastolic'},
    'notes': <String, dynamic>{'type': 'string', 'title': 'Notes'},
  },
};

Map<String, dynamic> _control(String property) => <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/$property',
    };

void main() {
  group('OmfTableRow rules', () {
    // A row is the layout itself, so it never reaches the dispatcher — its
    // rule was silently ignored and every row rendered, always. A CAM-ICU
    // worksheet asks Feature 2 only once Feature 1 is present, so presenting
    // all four at once is not how the instrument is administered.
    Map<String, dynamic> stepwise() => <String, dynamic>{
          'type': 'VerticalLayout',
          'elements': <dynamic>[
            <String, dynamic>{
              'type': 'OmfTableLayout',
              'elements': <dynamic>[
                <String, dynamic>{
                  'type': 'OmfTableRow',
                  'label': 'Feature 1',
                  'elements': <dynamic>[_control('systolic')],
                },
                <String, dynamic>{
                  'type': 'OmfTableRow',
                  'label': 'Feature 2',
                  'rule': <String, dynamic>{
                    'effect': 'SHOW',
                    'condition': <String, dynamic>{
                      'scope': '#/properties/systolic',
                      'schema': <String, dynamic>{
                        'type': 'integer',
                        'minimum': 1,
                      },
                    },
                  },
                  'elements': <dynamic>[_control('diastolic')],
                },
                <String, dynamic>{
                  'type': 'OmfTableRow',
                  'label': 'Feature 3',
                  'rule': <String, dynamic>{
                    'effect': 'DISABLE',
                    'condition': <String, dynamic>{
                      'scope': '#/properties/systolic',
                      'schema': <String, dynamic>{
                        'type': 'integer',
                        'minimum': 1,
                      },
                    },
                  },
                  'elements': <dynamic>[_control('notes')],
                },
              ],
            },
          ],
        };

    testWidgets('a SHOW rule keeps the row out until its condition holds',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(dataSchema: _schema, layout: stepwise()),
      );

      expect(find.text('Feature 1'), findsOneWidget);
      expect(find.text('Feature 2'), findsNothing);
      expect(find.text('Feature 3'), findsOneWidget);
    });

    testWidgets('the row appears once the earlier feature is answered',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(dataSchema: _schema, layout: stepwise()),
        initialData: <String, dynamic>{'systolic': 120},
      );

      expect(find.text('Feature 2'), findsOneWidget);
    });

    testWidgets("a row's DISABLE is ANDed into every cell it contains",
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(dataSchema: _schema, layout: stepwise()),
        initialData: <String, dynamic>{'systolic': 120},
      );

      // Feature 3's cell is disabled; the unruled Feature 1 cell is not.
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.map((field) => field.enabled), <bool>[true, true, false]);
    });
  });

  group('OmfTableLayout', () {
    testWidgets('column mode draws a header and suppresses cell labels',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{
                'type': 'OmfTableLayout',
                'options': <String, dynamic>{
                  'omf': <String, dynamic>{
                    'columns': <dynamic>[
                      <String, dynamic>{'key': 'sys', 'label': 'Systolic'},
                      <String, dynamic>{'key': 'dia', 'label': 'Diastolic'},
                    ],
                  },
                },
                'elements': <dynamic>[
                  <String, dynamic>{
                    'type': 'OmfTableRow',
                    'elements': <dynamic>[
                      _control('systolic'),
                      _control('diastolic'),
                    ],
                  },
                ],
              },
            ],
          },
        ),
      );

      // The header names each column, so the cells must not repeat it — one
      // "Systolic" on screen, not two.
      expect(find.text('Systolic'), findsOneWidget);
      expect(find.text('Diastolic'), findsOneWidget);
      expect(tester.widgetList(find.byType(TextField)), hasLength(2));
    });

    testWidgets('label mode draws a row label beside its contents',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{
                'type': 'OmfTableLayout',
                'elements': <dynamic>[
                  <String, dynamic>{
                    'type': 'OmfTableRow',
                    'label': 'Blood pressure',
                    'elements': <dynamic>[_control('systolic')],
                  },
                ],
              },
            ],
          },
        ),
      );

      expect(find.text('Blood pressure'), findsOneWidget);
      expect(tester.widgetList(find.byType(TextField)), hasLength(1));
    });
  });

  group('OmfTabsLayout', () {
    Map<String, dynamic> tabs() => <String, dynamic>{
          'type': 'VerticalLayout',
          'elements': <dynamic>[
            <String, dynamic>{
              'type': 'OmfTabsLayout',
              'elements': <dynamic>[
                <String, dynamic>{
                  'type': 'VerticalLayout',
                  'label': 'Observations',
                  'elements': <dynamic>[_control('systolic')],
                },
                <String, dynamic>{
                  'type': 'VerticalLayout',
                  'label': 'Notes',
                  'elements': <dynamic>[_control('notes')],
                },
              ],
            },
          ],
        };

    testWidgets('mounts only the active page', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(dataSchema: _schema, layout: tabs()),
      );

      // Both tab labels show, but only the first page's field is built.
      // Mounting hidden pages would run their rules and validation for content
      // the clinician cannot see.
      expect(find.text('Observations'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(tester.widgetList(find.byType(TextField)), hasLength(1));
      expect(find.text('Systolic'), findsOneWidget);
    });

    testWidgets('switching tabs swaps which page is mounted', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(dataSchema: _schema, layout: tabs()),
      );

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();

      expect(find.text('Systolic'), findsNothing);
      expect(tester.widgetList(find.byType(TextField)), hasLength(1));
    });
  });

  group('Group extras', () {
    testWidgets('a scored group shows a live subtotal', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'sepsis': <String, dynamic>{'type': 'boolean', 'title': 'Sepsis'},
            },
          },
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{
                'type': 'Group',
                'label': 'Risk factors',
                'elements': <dynamic>[
                  <String, dynamic>{
                    'type': 'Control',
                    'scope': '#/properties/sepsis',
                    'options': <String, dynamic>{
                      'omf': <String, dynamic>{'points': 5},
                    },
                  },
                ],
              },
            ],
          },
        ),
        initialData: const <String, dynamic>{'sepsis': true},
      );

      expect(find.text('Σ 5'), findsOneWidget);
    });

    testWidgets('a subsection indents without drawing a box', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{
                'type': 'Group',
                'label': 'Plus one or more of',
                'options': <String, dynamic>{
                  'omf': <String, dynamic>{'variant': 'subsection'},
                },
                'elements': <dynamic>[_control('notes')],
              },
            ],
          },
        ),
      );

      expect(find.text('Plus one or more of'), findsOneWidget);
      expect(find.byType(OmfGroupLayout), findsOneWidget);
    });
  });
}
