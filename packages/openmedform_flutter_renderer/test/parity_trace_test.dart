/// The ADR-003 cross-renderer parity trace.
///
/// ADR-003 requires the same form, filled the same way, to produce the same
/// submission payload in every renderer. This replays a scripted sequence of
/// clinician interactions against the Flutter renderer and records the payload
/// after **each** step.
///
/// Step by step, not just at the end: two renderers can disagree in the middle —
/// one writing `false` where the other deletes a key — and still converge on the
/// same final object. The interesting steps here are the ones that force that
/// disagreement: an unchecked matrix cell, a cleared field, an unchecked
/// boolean.
///
/// The recorded trace is checked in as `test/parity/parity_trace.flutter.json`
/// and is the reference the React renderer must reproduce. When
/// `parity_trace.json` (the React half, from `tool/parity_export.tsx`) is
/// present, this test diffs the two step by step; until then it records the
/// Flutter side and reports the comparison as pending. See docs/PARITY.md.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'ward': <String, dynamic>{'type': 'string', 'title': 'Ward'},
    'handover': <String, dynamic>{'type': 'string', 'title': 'Handover'},
    'spo2': <String, dynamic>{'type': 'integer', 'title': 'SpO2'},
    'sepsis': <String, dynamic>{'type': 'boolean', 'title': 'Sepsis'},
    'avpu': <String, dynamic>{
      'type': 'string',
      'title': 'AVPU',
      'enum': <String>['ALERT', 'VOICE', 'PAIN'],
    },
    'anticoagulant': <String, dynamic>{
      'type': 'string',
      'title': 'On anticoagulants',
      'enum': <String>['YES', 'NO'],
    },
    'rounds': <String, dynamic>{'type': 'object', 'title': 'Rounds'},
    'vte': <String, dynamic>{'type': 'object', 'title': 'VTE risk'},
  },
};

Map<String, dynamic> _control(String property, [Map<String, dynamic>? omf]) =>
    <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/$property',
      if (omf != null) 'options': <String, dynamic>{'omf': omf},
    };

final _layout = <String, dynamic>{
  'type': 'VerticalLayout',
  'elements': <dynamic>[
    _control('ward'),
    _control('handover', <String, dynamic>{'control': 'textarea'}),
    _control('spo2'),
    _control('sepsis', <String, dynamic>{'points': 3}),
    _control('avpu'),
    _control('anticoagulant', <String, dynamic>{'control': 'radio'}),
    _control('rounds', <String, dynamic>{
      'control': 'checklistMatrix',
      'rows': <dynamic>[
        <String, dynamic>{'key': 'pressure', 'label': 'Pressure area care'},
        <String, dynamic>{'key': 'mouth', 'label': 'Mouth care'},
      ],
      'columns': <dynamic>[
        <String, dynamic>{'key': 'd1', 'label': 'Day 1'},
        <String, dynamic>{'key': 'd2', 'label': 'Day 2'},
      ],
    }),
    _control('vte', <String, dynamic>{
      'control': 'scoringMatrix',
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
    }),
  ],
};

/// The script, mirroring `tool/parity_export.tsx` exactly.
const _steps = <Map<String, dynamic>>[
  {'action': 'fillText', 'label': 'Ward', 'value': 'ICU 3'},
  {
    'action': 'fillText',
    'label': 'Handover',
    'value': 'Deteriorating overnight'
  },
  {'action': 'fillNumber', 'label': 'SpO2', 'value': '88'},
  {'action': 'check', 'label': 'Sepsis'},
  {'action': 'selectOption', 'label': 'AVPU', 'value': 'VOICE'},
  {'action': 'chooseRadio', 'label': 'On anticoagulants', 'value': 'YES'},
  {
    'action': 'toggleMatrixCell',
    'row': 'Pressure area care',
    'column': 'Day 1'
  },
  {
    'action': 'toggleMatrixCell',
    'row': 'Pressure area care',
    'column': 'Day 2'
  },
  // Unchecking must DELETE the key, not write false.
  {
    'action': 'toggleMatrixCell',
    'row': 'Pressure area care',
    'column': 'Day 1'
  },
  {'action': 'toggleScoringItem', 'label': 'Immobile'},
  {'action': 'toggleScoringItem', 'label': 'Bed rest'},
  // Clearing a field must remove it, not store an empty string.
  {'action': 'fillText', 'label': 'Ward', 'value': ''},
  {'action': 'uncheck', 'label': 'Sepsis'},
];

Finder _fieldAfterLabel(String label) {
  // Every control renders its label above its input inside one FieldFrame.
  return find.descendant(
    of: find
        .ancestor(of: find.text(label), matching: find.byType(FieldFrame))
        .first,
    matching: find.byType(TextField),
  );
}

Future<void> _apply(WidgetTester tester, Map<String, dynamic> step) async {
  switch (step['action']) {
    case 'fillText':
    case 'fillNumber':
      await tester.enterText(
        _fieldAfterLabel(step['label'] as String).first,
        step['value'] as String,
      );

    case 'check':
    case 'uncheck':
      await tester.tap(
        find
                .ancestor(
                  of: find.text(step['label'] as String),
                  matching: find.byType(Row),
                )
                .first
                .evaluate()
                .isNotEmpty
            ? find
                .descendant(
                  of: find
                      .ancestor(
                        of: find.text(step['label'] as String),
                        matching: find.byType(Row),
                      )
                      .first,
                  matching: find.byType(Checkbox),
                )
                .first
            : find.byType(Checkbox).first,
      );

    case 'selectOption':
      await tester.tap(find.byType(DropdownButtonFormField<Object?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(step['value'] as String).last);

    case 'chooseRadio':
      await tester.tap(find.text(step['value'] as String).first);

    case 'toggleMatrixCell':
      await tester.tap(
        find.descendant(
          of: find.bySemanticsLabel('${step['row']} — ${step['column']}'),
          matching: find.byType(Checkbox),
        ),
      );

    case 'toggleScoringItem':
      // The checkbox sits in the same table row as its label.
      final row = find
          .ancestor(
            of: find.text(step['label'] as String),
            matching: find.byType(IntrinsicHeight),
          )
          .first;
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)).first,
      );
  }

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('records the payload after each scripted interaction',
      (tester) async {
    Map<String, dynamic> latest = <String, dynamic>{};

    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout),
      onChange: (data) => latest = data,
    );

    final trace = <Map<String, dynamic>>[];
    for (final step in _steps) {
      await _apply(tester, step);
      trace.add(<String, dynamic>{
        'step': step,
        // Snapshot, so later writes cannot rewrite history.
        'payload': jsonDecode(jsonEncode(latest)),
      });
    }

    // The shapes ADR-003 actually cares about.
    final finalPayload = trace.last['payload'] as Map<String, dynamic>;

    expect(
      finalPayload.containsKey('ward'),
      isFalse,
      reason: 'a cleared field is removed, not stored as an empty string',
    );
    expect(finalPayload['spo2'], isA<int>(),
        reason: 'a numeric field stores a number, never a string');
    expect(finalPayload['sepsis'], isFalse);
    expect(
      (finalPayload['rounds'] as Map<String, dynamic>)['pressure'],
      <String, dynamic>{'d2': true},
      reason: 'an unchecked matrix cell is deleted, not set to false',
    );
    expect(
      finalPayload['vte'],
      <String, dynamic>{'immobile': true, 'bedrest': true},
    );

    final directory = Directory('test/parity')..createSync(recursive: true);
    File('${directory.path}/parity_trace.flutter.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'note': 'Recorded from the Flutter renderer by '
                'parity_trace_test.dart. This is the reference the React '
                'renderer must reproduce — see docs/PARITY.md.',
            'trace': trace,
          })}\n',
    );
  });

  test('matches the React renderer step for step', () {
    final react = File('test/parity/parity_trace.json');
    final flutter = File('test/parity/parity_trace.flutter.json');

    if (!react.existsSync()) {
      markTestSkipped(
        'No React trace yet. Generate one with tool/parity_export.tsx; it is '
        'currently blocked on the monorepo\'s React test environment, where '
        'fireEvent does not reach the renderer\'s handlers. See docs/PARITY.md.',
      );
      return;
    }

    final expected = (jsonDecode(react.readAsStringSync())
        as Map<String, dynamic>)['trace'] as List<dynamic>;
    final actual = (jsonDecode(flutter.readAsStringSync())
        as Map<String, dynamic>)['trace'] as List<dynamic>;

    expect(actual, hasLength(expected.length),
        reason: 'both renderers must run the same script');

    for (var i = 0; i < expected.length; i++) {
      final step = (expected[i] as Map<String, dynamic>)['step'];
      expect(
        (actual[i] as Map<String, dynamic>)['payload'],
        (expected[i] as Map<String, dynamic>)['payload'],
        reason: 'payloads diverged after step ${i + 1}: $step',
      );
    }
  });
}
