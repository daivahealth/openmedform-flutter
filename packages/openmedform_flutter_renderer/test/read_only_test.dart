/// Read-only mode, across every control.
///
/// Replay renders a completed submission. If any control stays writable there,
/// a clinician can silently alter a signed record — so this sweeps the whole
/// inventory rather than spot-checking.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'text': <String, dynamic>{'type': 'string', 'title': 'Text'},
    'notes': <String, dynamic>{'type': 'string', 'title': 'Notes'},
    'count': <String, dynamic>{'type': 'integer', 'title': 'Count'},
    'flag': <String, dynamic>{'type': 'boolean', 'title': 'Flag'},
    'choice': <String, dynamic>{
      'type': 'string',
      'title': 'Choice',
      'enum': <String>['A', 'B'],
    },
    'pick': <String, dynamic>{
      'type': 'string',
      'title': 'Pick',
      'enum': <String>['X', 'Y'],
    },
    'when': <String, dynamic>{
      'type': 'string',
      'format': 'date',
      'title': 'When',
    },
    'signature': <String, dynamic>{'type': 'object', 'title': 'Signature'},
    'matrix': <String, dynamic>{'type': 'object', 'title': 'Matrix'},
    'scoring': <String, dynamic>{'type': 'object', 'title': 'Scoring'},
    'rounds': <String, dynamic>{
      'type': 'array',
      'title': 'Round',
      'items': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'nurse': <String, dynamic>{'type': 'string', 'title': 'Nurse'},
          'note': <String, dynamic>{'type': 'string', 'title': 'Note'},
        },
      },
    },
  },
};

Map<String, dynamic> _control(String property, {Map<String, dynamic>? omf}) =>
    <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/$property',
      if (omf != null) 'options': <String, dynamic>{'omf': omf},
    };

final _layout = <String, dynamic>{
  'type': 'VerticalLayout',
  'elements': <dynamic>[
    _control('text'),
    _control('notes', omf: <String, dynamic>{'control': 'textarea'}),
    _control('count'),
    _control('flag'),
    _control('choice'),
    _control('pick', omf: <String, dynamic>{'control': 'radio'}),
    _control('when'),
    _control('signature', omf: <String, dynamic>{'control': 'signatureDate'}),
    _control(
      'matrix',
      omf: <String, dynamic>{
        'control': 'checklistMatrix',
        'rows': <dynamic>[
          <String, dynamic>{'key': 'r1', 'label': 'Row 1'},
        ],
        'columns': <dynamic>[
          <String, dynamic>{'key': 'c1', 'label': 'Col 1'},
        ],
      },
    ),
    _control(
      'scoring',
      omf: <String, dynamic>{
        'control': 'scoringMatrix',
        'domains': <dynamic>[
          <String, dynamic>{
            'items': <dynamic>[
              <String, dynamic>{'field': 'f1', 'label': 'Factor', 'points': 2},
            ],
          },
        ],
      },
    ),
    _control(
      'rounds',
      omf: <String, dynamic>{
        'control': 'recordTable',
        'recordTable': <String, dynamic>{
          'columns': <dynamic>[
            <String, dynamic>{'label': 'Nurse', 'path': 'nurse'},
          ],
        },
      },
    ),
  ],
};

const _data = <String, dynamic>{
  'text': 'typed',
  'notes': 'a longer note',
  'count': 7,
  'flag': true,
  'choice': 'A',
  'pick': 'X',
  'when': '2026-08-01',
  'signature': <String, dynamic>{
    'printedName': 'A. Nurse',
    'date': '2026-08-01'
  },
  'matrix': <String, dynamic>{
    'r1': <String, dynamic>{'c1': true},
  },
  'scoring': <String, dynamic>{'f1': true},
  'rounds': <dynamic>[
    <String, dynamic>{'nurse': 'A. Nurse', 'note': 'settled'},
  ],
};

void main() {
  testWidgets('no input anywhere in the form accepts a change', (tester) async {
    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout),
      initialData: _data,
      readOnly: true,
    );

    expect(tester.takeException(), isNull);

    final textFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(textFields, isNotEmpty);
    for (final field in textFields) {
      expect(field.enabled, isFalse, reason: 'a text field stayed writable');
    }

    final formFields =
        tester.widgetList<TextFormField>(find.byType(TextFormField));
    for (final field in formFields) {
      expect(field.enabled, isNotNull);
    }

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes, isNotEmpty);
    for (final box in checkboxes) {
      expect(box.onChanged, isNull, reason: 'a checkbox stayed writable');
    }

    for (final radio in tester.widgetList<Radio<Object?>>(
      find.byType(Radio<Object?>),
    )) {
      expect(radio.enabled, isFalse, reason: 'a radio stayed writable');
    }

    for (final dropdown in tester.widgetList<DropdownButtonFormField<Object?>>(
      find.byType(DropdownButtonFormField<Object?>),
    )) {
      expect(dropdown.onChanged, isNull, reason: 'a dropdown stayed writable');
    }
  });

  testWidgets('the store refuses writes even if a control tries',
      (tester) async {
    // Belt and braces: `enabled` is a rendering concern, but the store is the
    // thing that would actually mutate a signed record.
    Map<String, dynamic>? seen;

    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout),
      initialData: _data,
      readOnly: true,
      onChange: (data) => seen = data,
    );

    // FormScope sits *below* the renderer, so read it from a descendant.
    final store = FormScope.read(tester.element(find.byType(TextField).first));

    store
      ..updateAt(<String>['text'], 'tampered')
      ..removeAt(<String>['count']);

    expect(store.data['text'], 'typed');
    expect(store.data.containsKey('count'), isTrue);
    expect(seen, isNull, reason: 'a read-only store must not notify a host');
  });

  testWidgets('the record table hides its add and remove affordances',
      (tester) async {
    await pumpForm(
      tester,
      definition: definitionOf(dataSchema: _schema, layout: _layout),
      initialData: _data,
      readOnly: true,
    );

    // Adding or removing a record is a write; on a completed submission the
    // buttons should not be offered at all.
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '+ Add Round'),
    );
    expect(addButton.onPressed, isNull);

    expect(
      find.byIcon(Icons.close),
      findsNothing,
      reason: 'remove should not be offered on a read-only table',
    );
  });
}
