/// Scored single-selects, and the labels a bare `enum` gets from the UI schema.
///
/// Both hang off `options.omf` on the *element*, so a control that resolves its
/// choices from the schema alone cannot see either. Morse Fall is the shape:
/// "Ambulatory aid" is none 0, crutches 15, furniture 30 — the choice carries
/// the score, not a tick.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'morse': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'aid': <String, dynamic>{
          'title': 'Ambulatory aid',
          'enum': <dynamic>['NONE', 'CRUTCHES', 'FURNITURE'],
        },
      },
    },
  },
};

const _aid = <String, dynamic>{
  'type': 'Control',
  'scope': '#/properties/morse/properties/aid',
  'options': <String, dynamic>{
    'omf': <String, dynamic>{
      'control': 'radio',
      'optionLabels': <String, dynamic>{
        'NONE': 'None / bed rest / nurse assist',
        'CRUTCHES': 'Crutches / cane / walker',
        'FURNITURE': 'Furniture',
      },
      'optionPoints': <String, dynamic>{
        'NONE': 0,
        'CRUTCHES': 15,
        'FURNITURE': 30,
      },
    },
  },
};

Map<String, dynamic> _layout() => <String, dynamic>{
      'type': 'VerticalLayout',
      'elements': <dynamic>[
        <String, dynamic>{
          'type': 'Group',
          'label': 'MORSE FALL',
          'elements': <dynamic>[_aid],
        },
      ],
    };

void main() {
  testWidgets('optionLabels name the choices of a bare enum', (tester) async {
    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout()),
    );

    expect(find.text('Crutches / cane / walker'), findsOneWidget);
    // Showing the code would put CRUTCHES in front of a clinician.
    expect(find.text('CRUTCHES'), findsNothing);
  });

  testWidgets('the selected choice contributes its own points', (tester) async {
    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout()),
      initialData: <String, dynamic>{
        'morse': <String, dynamic>{'aid': 'CRUTCHES'},
      },
    );

    expect(find.text('Σ 15'), findsOneWidget);
  });

  testWidgets('a section scored only by selects still draws a subtotal',
      (tester) async {
    // showsSectionSubtotal asks whether the section has scored items of its
    // own. Before selects were collected, the answer here was no and the box
    // drew nothing at all where the web renderers drew a chip.
    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout()),
    );

    expect(find.text('Σ 0'), findsOneWidget);
  });

  testWidgets('the stored code keeps its schema type', (tester) async {
    Map<String, dynamic>? written;
    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout()),
      onChange: (data) => written = data,
    );

    await tester.tap(find.text('Furniture'));
    await tester.pumpAndSettle();

    expect(written?['morse'], <String, dynamic>{'aid': 'FURNITURE'});
    expect(find.text('Σ 30'), findsOneWidget);
  });
}
