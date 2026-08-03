/// The clinical controls, and the value shapes they write.
///
/// Value derivation is what ADR-003 actually constrains, so these assert the
/// data each control produces rather than only that it draws.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

Map<String, dynamic> _controlOf(
  String property,
  String control, {
  Map<String, dynamic> omf = const <String, dynamic>{},
  String? title,
}) =>
    <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/$property',
      if (title != null) 'label': title,
      'options': <String, dynamic>{
        'omf': <String, dynamic>{'control': control, ...omf},
      },
    };

Map<String, dynamic> _layoutOf(Map<String, dynamic> element) =>
    <String, dynamic>{
      'type': 'VerticalLayout',
      'elements': <dynamic>[element],
    };

void main() {
  group('radio', () {
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'anticoagulant': <String, dynamic>{
          'type': 'string',
          'title': 'On anticoagulants',
          'enum': <String>['YES', 'NO'],
        },
        'avpu': <String, dynamic>{
          'type': 'string',
          'title': 'AVPU',
          'enum': <String>['ALERT', 'VOICE', 'PAIN', 'UNRESPONSIVE'],
        },
      },
    };

    testWidgets('renders one button per enum option', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layoutOf(_controlOf('avpu', 'radio')),
        ),
      );

      expect(tester.widgetList(find.byType(Radio<Object?>)), hasLength(4));
      expect(find.text('ALERT'), findsOneWidget);
      expect(find.text('UNRESPONSIVE'), findsOneWidget);
    });

    testWidgets('writes the selected code', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layoutOf(_controlOf('avpu', 'radio')),
        ),
        onChange: (data) => seen = data,
      );

      await tester.tap(find.text('VOICE'));
      await tester.pump();

      // Stored values are language-independent codes, never display text.
      expect(seen?['avpu'], 'VOICE');
    });

    testWidgets('a two-option enum defaults to label-left', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layoutOf(_controlOf('anticoagulant', 'radio')),
        ),
      );

      // The paper YES/NO row: the label sits on the same line as its options,
      // so both are laid out inside one Row.
      final label = find.text('On anticoagulants');
      expect(label, findsOneWidget);

      final labelBox = tester.getRect(label);
      final yesBox = tester.getRect(find.text('YES'));
      expect(
        labelBox.center.dy,
        closeTo(yesBox.center.dy, 4),
        reason: 'label and options should share a line',
      );
      expect(labelBox.left, lessThan(yesBox.left));
    });
  });

  group('checklistMatrix', () {
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'rounds': <String, dynamic>{'type': 'object', 'title': 'Rounds'},
      },
    };

    final element = _controlOf(
      'rounds',
      'checklistMatrix',
      omf: <String, dynamic>{
        'rows': <dynamic>[
          <String, dynamic>{'key': 'pressure', 'label': 'Pressure area care'},
          <String, dynamic>{'key': 'mouth', 'label': 'Mouth care'},
        ],
        'columns': <dynamic>[
          <String, dynamic>{'key': 'd1', 'label': 'Day 1'},
          <String, dynamic>{'key': 'd2', 'label': 'Day 2'},
        ],
      },
    );

    testWidgets('draws a checkbox per row and column', (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
      );

      expect(tester.widgetList(find.byType(Checkbox)), hasLength(4));
      expect(find.text('Pressure area care'), findsOneWidget);
      expect(find.text('Day 2'), findsOneWidget);
    });

    testWidgets('checking writes a nested true', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(seen?['rounds'], <String, dynamic>{
        'pressure': <String, dynamic>{'d1': true},
      });
    });

    testWidgets('unchecking DELETES the key rather than storing false',
        (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
        initialData: <String, dynamic>{
          'rounds': <String, dynamic>{
            'pressure': <String, dynamic>{'d1': true, 'd2': true},
          },
        },
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      // Writing `false` here would produce different submission JSON than the
      // web renderers do for the same clinical input.
      final rounds = seen?['rounds'] as Map<String, dynamic>;
      final pressure = rounds['pressure'] as Map<String, dynamic>;
      expect(pressure.containsKey('d1'), isFalse);
      expect(pressure['d2'], isTrue);
    });

    testWidgets('emptying a row removes the row itself', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
        initialData: <String, dynamic>{
          'rounds': <String, dynamic>{
            'pressure': <String, dynamic>{'d1': true},
          },
        },
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect((seen?['rounds'] as Map).containsKey('pressure'), isFalse);
    });
  });

  group('scoringMatrix', () {
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'vte': <String, dynamic>{'type': 'object', 'title': 'VTE risk'},
      },
    };

    final element = _controlOf(
      'vte',
      'scoringMatrix',
      omf: <String, dynamic>{
        'domains': <dynamic>[
          <String, dynamic>{
            'name': 'Mobility',
            'items': <dynamic>[
              <String, dynamic>{
                'field': 'bedrest',
                'label': 'Bed rest',
                'points': 1,
              },
              <String, dynamic>{
                'field': 'immobile',
                'label': 'Immobile',
                'points': 3,
              },
            ],
          },
        ],
      },
    );

    testWidgets('shows the domain, its items and a subtotal', (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
      );

      expect(find.text('Risk Factor'), findsOneWidget);
      expect(find.text('Mobility'), findsOneWidget);
      expect(find.text('Bed rest'), findsOneWidget);
      expect(find.textContaining('Subtotal'), findsOneWidget);
    });

    testWidgets('the subtotal reflects what is ticked', (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
        initialData: <String, dynamic>{
          'vte': <String, dynamic>{'immobile': true},
        },
      );

      // 3 points ticked. The footer shows it; the server still recalculates.
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('ticking writes a flat field map', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: schema, layout: _layoutOf(element)),
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(seen?['vte'], <String, dynamic>{'bedrest': true});
    });
  });

  group('signatureDate', () {
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'signature': <String, dynamic>{
          'type': 'object',
          'title': 'Nurse signature',
        },
      },
    };

    testWidgets('writes a composite of printed name and date', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: schema,
          layout: _layoutOf(_controlOf('signature', 'signatureDate')),
        ),
        onChange: (data) => seen = data,
      );

      await tester.enterText(find.byType(TextFormField), 'A. Nurse');
      await tester.pump();

      expect(seen?['signature'], <String, dynamic>{'printedName': 'A. Nurse'});
    });
  });

  group('display-only controls', () {
    testWidgets('riskStratification says the server will compute it',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'risk': <String, dynamic>{'type': 'string', 'title': 'Risk'},
            },
          },
          layout: _layoutOf(_controlOf('risk', 'riskStratification')),
        ),
      );

      expect(find.text('Calculated on submission'), findsOneWidget);
    });

    testWidgets('riskStratification echoes a stored value', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'risk': <String, dynamic>{'type': 'string', 'title': 'Risk'},
            },
          },
          layout: _layoutOf(_controlOf('risk', 'riskStratification')),
        ),
        initialData: const <String, dynamic>{'risk': 'HIGH'},
      );

      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('Calculated on submission'), findsNothing);
    });

    testWidgets('clinicalReferenceTable prints its static rows',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'ref': <String, dynamic>{'type': 'string'},
            },
          },
          layout: _layoutOf(
            _controlOf(
              'ref',
              'clinicalReferenceTable',
              omf: <String, dynamic>{
                'headers': <String>['Score', 'Action'],
                'rows': <dynamic>[
                  <String>['0-4', 'Routine'],
                  <String>['5+', 'Escalate'],
                ],
              },
            ),
          ),
        ),
      );

      expect(find.text('Score'), findsOneWidget);
      expect(find.text('Escalate'), findsOneWidget);
    });

    testWidgets('vitalSignsChart tabulates recorded rows', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'obs': <String, dynamic>{
                'type': 'array',
                'title': 'Observations'
              },
            },
          },
          layout: _layoutOf(
            _controlOf(
              'obs',
              'vitalSignsChart',
              omf: <String, dynamic>{
                'columns': <dynamic>[
                  <String, dynamic>{'key': 'time', 'label': 'Time'},
                  <String, dynamic>{'key': 'hr', 'label': 'HR'},
                ],
              },
            ),
          ),
        ),
        initialData: const <String, dynamic>{
          'obs': <dynamic>[
            <String, dynamic>{'time': '08:00', 'hr': 120},
          ],
        },
      );

      expect(find.text('Time'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
    });
  });

  group('scoreSummary', () {
    testWidgets('totals scored controls across every section', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: const <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'age': <String, dynamic>{
                'type': 'object',
                'properties': <String, dynamic>{
                  'over75': <String, dynamic>{
                    'type': 'boolean',
                    'title': 'Over 75',
                  },
                },
              },
              'total': <String, dynamic>{'type': 'number'},
            },
          },
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{
                'type': 'Group',
                'label': 'AGE',
                'elements': <dynamic>[
                  <String, dynamic>{
                    'type': 'Control',
                    'scope': '#/properties/age/properties/over75',
                    'options': <String, dynamic>{
                      'omf': <String, dynamic>{'points': 3},
                    },
                  },
                ],
              },
              _controlOf(
                'total',
                'scoreSummary',
                title: 'Total Score',
                omf: <String, dynamic>{
                  'bands': <dynamic>[
                    <String, dynamic>{'maxScore': 2, 'label': 'Low'},
                    <String, dynamic>{'minScore': 3, 'label': 'High'},
                  ],
                },
              ),
            ],
          },
        ),
        initialData: const <String, dynamic>{
          'age': <String, dynamic>{'over75': true},
        },
      );

      expect(find.text('3'), findsWidgets);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('AGE'), findsWidgets);
      expect(find.textContaining('server recalculates'), findsOneWidget);
    });
  });
}
