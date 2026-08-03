/// `recordTable`.
///
/// Cases transliterated from `record-table.test.tsx` in the React renderer,
/// plus the Dart-specific ones the TypeScript could not have (list-crossing
/// paths, the item-schema root).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

const _itemSchema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'date': <String, dynamic>{
      'type': 'string',
      'format': 'date',
      'title': 'Date',
    },
    'nurse': <String, dynamic>{'type': 'string', 'title': 'Nurse'},
    'grbs': <String, dynamic>{'type': 'integer', 'title': 'GRBS'},
    'notes': <String, dynamic>{'type': 'string', 'title': 'Notes'},
    'adverseEvents': <String, dynamic>{'type': 'array'},
  },
};

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'treatments': <String, dynamic>{
      'type': 'array',
      'title': 'Treatment day',
      'items': _itemSchema,
    },
  },
};

Map<String, dynamic> _element({
  Map<String, dynamic> recordTable = const <String, dynamic>{},
  Map<String, dynamic>? detail,
  bool configured = true,
}) =>
    <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/treatments',
      'options': <String, dynamic>{
        if (detail != null) 'detail': detail,
        'omf': <String, dynamic>{
          if (configured) 'control': 'recordTable',
          if (recordTable.isNotEmpty) 'recordTable': recordTable,
        },
      },
    };

Map<String, dynamic> _layout(Map<String, dynamic> element) => <String, dynamic>{
      'type': 'VerticalLayout',
      'elements': <dynamic>[element],
    };

const _columns = <dynamic>[
  <String, dynamic>{'label': 'Date', 'path': 'date'},
  <String, dynamic>{'label': 'Nurse', 'path': 'nurse'},
  <String, dynamic>{'label': 'Events', 'countOf': 'adverseEvents'},
];

void main() {
  group('tester', () {
    testWidgets('claims an explicit recordTable', (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: _schema, layout: _layout(_element())),
      );

      expect(find.byType(OmfRecordTable), findsOneWidget);
      expect(find.byType(UnknownElementWidget), findsNothing);
    });

    testWidgets('also claims an unconfigured array of objects', (tester) async {
      // The safety net: without it this would fall through to a generic list
      // widget, which is unusable on a clinical form.
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(<String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/treatments',
          }),
        ),
      );

      expect(find.byType(OmfRecordTable), findsOneWidget);
    });

    testWidgets('derives columns when none are configured', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(<String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/treatments',
          }),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'}
          ],
        },
      );

      // The first four scalar properties, titled; the array is skipped.
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('NURSE'), findsOneWidget);
      expect(find.text('GRBS'), findsOneWidget);
    });
  });

  group('empty state and toolbar', () {
    testWidgets('shows the empty label and a count of zero', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': _columns,
                'emptyLabel': 'No treatment days yet.',
                'countLabel': '{n} treatment day{s} logged',
              },
            ),
          ),
        ),
      );

      expect(find.text('No treatment days yet.'), findsOneWidget);
      expect(find.text('0 treatment days logged'), findsOneWidget);
    });

    testWidgets('the count line pluralises through form-core', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': _columns,
                'countLabel': '{n} treatment day{s} logged',
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'}
          ],
        },
      );

      expect(find.text('1 treatment day logged'), findsOneWidget);
    });
  });

  group('adding', () {
    testWidgets('seeds a record and opens it', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(recordTable: <String, dynamic>{'columns': _columns}),
          ),
        ),
        onChange: (data) => seen = data,
      );

      await tester.tap(find.textContaining('Add'));
      await tester.pumpAndSettle();

      final records = seen?['treatments'] as List<Object?>;
      expect(records, hasLength(1));

      // createRecordDefault seeds arrays so a summary path resolves straight
      // away — the events column must read 0, not an em dash.
      expect(
        (records.first as Map<String, dynamic>)['adverseEvents'],
        isEmpty,
      );

      // The new record is appended, so it is the one that opens.
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('uses a configured add label', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': _columns,
                'addLabel': '+ Add treatment day',
              },
            ),
          ),
        ),
      );

      expect(find.text('+ Add treatment day'), findsOneWidget);
    });
  });

  group('summary cells', () {
    testWidgets('derived columns render as read-only text', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(recordTable: <String, dynamic>{'columns': _columns}),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{
              'date': '2026-08-01',
              'nurse': 'A. Nurse',
              'adverseEvents': <dynamic>['rash', 'nausea'],
            },
          ],
        },
      );

      // countOf has no single value to write back, so it stays text.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('an editable column dispatches the real control',
        (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': <dynamic>[
                  <String, dynamic>{'label': 'Nurse', 'path': 'nurse'},
                ],
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'nurse': 'A. Nurse'}
          ],
        },
        onChange: (data) => seen = data,
      );

      // The cell is a real text control resolved against the ITEM schema, and
      // it writes to treatments.0.nurse.
      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      await tester.enterText(field, 'B. Nurse');
      await tester.pump();

      final records = seen?['treatments'] as List<Object?>;
      expect((records.first as Map<String, dynamic>)['nurse'], 'B. Nurse');
    });
  });

  group('detail panel', () {
    testWidgets('opens beneath the row and closes again', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(recordTable: <String, dynamic>{'columns': _columns}),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'}
          ],
        },
      );

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Notes'), findsNothing);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Generated from the item schema, since no options.detail was supplied.
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsNothing);
    });

    testWidgets('uses options.detail when the author supplied one',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{'columns': _columns},
              detail: <String, dynamic>{
                'type': 'VerticalLayout',
                'elements': <dynamic>[
                  <String, dynamic>{
                    'type': 'Control',
                    'scope': '#/properties/notes',
                    'label': 'Shift handover',
                  },
                ],
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'}
          ],
        },
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Shift handover'), findsOneWidget);
      // The generated layout would have shown every field; this one shows one.
      expect(find.text('GRBS'), findsNothing);
    });

    testWidgets('a detail field writes into the right record', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': <dynamic>[
                  <String, dynamic>{'label': 'Date', 'path': 'date'},
                ],
              },
              detail: <String, dynamic>{
                'type': 'VerticalLayout',
                'elements': <dynamic>[
                  <String, dynamic>{
                    'type': 'Control',
                    'scope': '#/properties/notes',
                  },
                ],
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'},
            <String, dynamic>{'date': '2026-08-02'},
          ],
        },
        onChange: (data) => seen = data,
      );

      // Open the SECOND row: its detail must write to index 1, not index 0.
      await tester.tap(find.text('Open').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, 'settled overnight');
      await tester.pump();

      final records = seen?['treatments'] as List<Object?>;
      expect((records[0] as Map<String, dynamic>)['notes'], isNull);
      expect(
        (records[1] as Map<String, dynamic>)['notes'],
        'settled overnight',
      );
    });

    testWidgets('the Open button is hidden when every field is a column',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'readings': <String, dynamic>{
                'type': 'array',
                'title': 'Reading',
                'items': <String, dynamic>{
                  'type': 'object',
                  'properties': <String, dynamic>{
                    'time': <String, dynamic>{'type': 'string'},
                  },
                },
              },
            },
          },
          layout: _layout(<String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/readings',
            'options': <String, dynamic>{
              'omf': <String, dynamic>{
                'control': 'recordTable',
                'recordTable': <String, dynamic>{
                  'columns': <dynamic>[
                    <String, dynamic>{'label': 'Time', 'path': 'time'},
                  ],
                },
              },
            },
          }),
        ),
        initialData: const <String, dynamic>{
          'readings': <dynamic>[
            <String, dynamic>{'time': '08:00'}
          ],
        },
      );

      // A panel would reveal an empty box, so the affordance is hidden.
      expect(find.text('Open'), findsNothing);
    });
  });

  group('removing', () {
    testWidgets('drops the record', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(recordTable: <String, dynamic>{'columns': _columns}),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'},
            <String, dynamic>{'date': '2026-08-02'},
          ],
        },
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      final records = seen?['treatments'] as List<Object?>;
      expect(records, hasLength(1));
      expect(
        (records.single as Map<String, dynamic>)['date'],
        '2026-08-02',
      );
    });

    testWidgets('asks first when removeConfirm is configured', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': _columns,
                'removeConfirm': 'Remove this treatment day?',
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'}
          ],
        },
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(find.text('Remove this treatment day?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(seen, isNull, reason: 'cancelling must not touch the data');
    });
  });

  group('column orientation', () {
    testWidgets('transposes into one column per record', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _layout(
            _element(
              recordTable: <String, dynamic>{
                'columns': _columns,
                'orientation': 'columns',
                'instanceLabel': 'Cannula',
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'treatments': <dynamic>[
            <String, dynamic>{'date': '2026-08-01'},
            <String, dynamic>{'date': '2026-08-02'},
          ],
        },
      );

      // Field labels run down the left; each record heads its own column.
      expect(find.text('PARAMETER'), findsOneWidget);
      expect(find.text('CANNULA 1'), findsOneWidget);
      expect(find.text('CANNULA 2'), findsOneWidget);
      expect(find.text('Date'), findsOneWidget);
    });
  });
}
