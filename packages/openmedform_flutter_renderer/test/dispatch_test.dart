/// Dispatch, rules, and the store's write behaviour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'situation': <String, dynamic>{'type': 'string', 'title': 'Situation'},
    'spo2': <String, dynamic>{
      'type': 'integer',
      'title': 'SpO2',
      'maximum': 100,
    },
    'urgent': <String, dynamic>{'type': 'boolean', 'title': 'Urgent'},
    'recommendation': <String, dynamic>{
      'type': 'string',
      'title': 'Recommendation',
    },
  },
  'required': <String>['situation'],
};

Map<String, dynamic> _control(String property) => <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/$property',
    };

void main() {
  group('unknown elements', () {
    testWidgets('an unrecognised element type renders a loud placeholder',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{'type': 'OmfPatientHeader'},
            ],
          },
        ),
      );

      expect(find.byType(UnknownElementWidget), findsOneWidget);
      expect(find.textContaining('OmfPatientHeader'), findsOneWidget);
    });

    testWidgets('an unimplemented clinical control names itself',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: <String, dynamic>{
            'type': 'object',
            'properties': <String, dynamic>{
              'rounds': <String, dynamic>{'type': 'array'},
            },
          },
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[
              <String, dynamic>{
                'type': 'Control',
                'scope': '#/properties/rounds',
                'options': <String, dynamic>{
                  'omf': <String, dynamic>{'control': 'recordTable'},
                },
              },
            ],
          },
        ),
      );

      // An array has no standard control to fall back to, so this is genuinely
      // unsupported until M5 (#6) — and says so.
      expect(find.textContaining('omf.control=recordTable'), findsOneWidget);
    });
  });

  group('rules', () {
    Map<String, dynamic> ruleLayout(String effect) => <String, dynamic>{
          'type': 'VerticalLayout',
          'elements': <dynamic>[
            _control('situation'),
            <String, dynamic>{
              ..._control('recommendation'),
              'rule': <String, dynamic>{
                'effect': effect,
                'condition': <String, dynamic>{
                  'scope': '#/properties/spo2',
                  'schema': <String, dynamic>{
                    'type': 'integer',
                    'maximum': 91,
                  },
                },
              },
            },
          ],
        };

    testWidgets('SHOW collapses the element until its condition holds',
        (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: _schema, layout: ruleLayout('SHOW')),
        initialData: <String, dynamic>{'spo2': 98},
      );

      expect(find.text('Recommendation'), findsNothing);
    });

    testWidgets('SHOW reveals the element once its condition holds',
        (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: _schema, layout: ruleLayout('SHOW')),
        initialData: <String, dynamic>{'spo2': 88},
      );

      expect(find.text('Recommendation'), findsOneWidget);
    });

    testWidgets('a rule re-evaluates as the data changes', (tester) async {
      final key = await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: _schema, layout: ruleLayout('SHOW')),
        initialData: <String, dynamic>{'spo2': 98},
      );

      expect(find.text('Recommendation'), findsNothing);

      // Rules are derived per build rather than stored, so a write is all it
      // takes for dependent elements to reappear.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      field.onChanged?.call('worsening');
      await tester.pump();

      key.currentState!.data['spo2'] = 88;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OmfFormRenderer(
              definition: definitionOf(
                dataSchema: _schema,
                layout: ruleLayout('SHOW'),
              ),
              initialData: const <String, dynamic>{'spo2': 88},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recommendation'), findsOneWidget);
    });

    testWidgets('DISABLE keeps the element visible but not editable',
        (tester) async {
      await pumpForm(
        tester,
        definition:
            definitionOf(dataSchema: _schema, layout: ruleLayout('DISABLE')),
        initialData: <String, dynamic>{'spo2': 88},
      );

      expect(find.text('Recommendation'), findsOneWidget);

      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.last.enabled, isFalse);
    });
  });

  group('store writes', () {
    testWidgets('a text control writes a string and reports it',
        (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[_control('situation')],
          },
        ),
        onChange: (data) => seen = data,
      );

      await tester.enterText(find.byType(TextField), 'chest pain');
      await tester.pump();

      expect(seen?['situation'], 'chest pain');
    });

    testWidgets('a numeric control writes a number, never a string',
        (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[_control('spo2')],
          },
        ),
        onChange: (data) => seen = data,
      );

      await tester.enterText(find.byType(TextField), '88');
      await tester.pump();

      // A text field forwarding its raw String would fail server-side
      // validation on a field the clinician filled in correctly.
      expect(seen?['spo2'], isA<int>());
      expect(seen?['spo2'], 88);
    });

    testWidgets(
        'clearing a field removes the value rather than storing an '
        'empty string', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[_control('situation')],
          },
        ),
        initialData: <String, dynamic>{'situation': 'chest pain'},
        onChange: (data) => seen = data,
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(seen?['situation'], isNull);
    });

    testWidgets('a checkbox writes a boolean', (tester) async {
      Map<String, dynamic>? seen;

      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[_control('urgent')],
          },
        ),
        onChange: (data) => seen = data,
      );

      await tester.tap(find.byType(Checkbox));
      await tester.pump();

      expect(seen?['urgent'], isTrue);
    });
  });

  group('validation surfacing', () {
    testWidgets('a required field shows its marker', (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[_control('situation')],
          },
        ),
      );

      expect(find.textContaining('Situation'), findsOneWidget);
      expect(find.textContaining('*'), findsOneWidget);
    });

    testWidgets('an out-of-range value surfaces an error under the field',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: <String, dynamic>{
            'type': 'VerticalLayout',
            'elements': <dynamic>[_control('spo2')],
          },
        ),
        initialData: <String, dynamic>{'spo2': 140},
      );

      expect(find.textContaining('maximum'), findsOneWidget);
    });
  });
}
