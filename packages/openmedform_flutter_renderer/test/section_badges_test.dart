/// The section-level scoring badges.
///
/// The visible half of a contract the conformance fixtures pin on the core
/// side: `showsSectionSubtotal` decides *where* a chip belongs, and this checks
/// the renderer actually asks.
library;

import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'q': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'rr': <String, dynamic>{'type': 'boolean', 'title': 'RR >= 22'},
        'gcs': <String, dynamic>{'type': 'boolean', 'title': 'Altered GCS'},
      },
    },
    's': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'temp': <String, dynamic>{'type': 'boolean', 'title': 'Temp'},
      },
    },
  },
};

Map<String, dynamic> _scored(String scope, num points) => <String, dynamic>{
      'type': 'Control',
      'scope': scope,
      'options': <String, dynamic>{
        'omf': <String, dynamic>{'points': points},
      },
    };

/// qSOFA and SIRS, each in its own box, inside an outer "Scoring Systems" box —
/// the shape from the Sepsis screening sheet upstream used to motivate this.
Map<String, dynamic> _sepsisLayout({
  Map<String, dynamic>? outerOmf,
  Map<String, dynamic>? qsofaOmf,
  List<dynamic>? sirsBands,
}) =>
    <String, dynamic>{
      'type': 'VerticalLayout',
      'elements': <dynamic>[
        <String, dynamic>{
          'type': 'Group',
          'label': 'Scoring Systems',
          if (outerOmf != null) 'options': <String, dynamic>{'omf': outerOmf},
          'elements': <dynamic>[
            <String, dynamic>{
              'type': 'Group',
              'label': 'qSOFA',
              if (qsofaOmf != null)
                'options': <String, dynamic>{'omf': qsofaOmf},
              'elements': <dynamic>[
                _scored('#/properties/q/properties/rr', 1),
                _scored('#/properties/q/properties/gcs', 1),
              ],
            },
            <String, dynamic>{
              'type': 'Group',
              'label': 'SIRS',
              if (sirsBands != null)
                'options': <String, dynamic>{
                  'omf': <String, dynamic>{'bands': sirsBands},
                },
              'elements': <dynamic>[
                _scored('#/properties/s/properties/temp', 1),
              ],
            },
          ],
        },
      ],
    };

Finder _chip(String text) => find.text(text);

void main() {
  group('section subtotal placement', () {
    testWidgets('only the innermost scoring sections draw a chip',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(dataSchema: _schema, layout: _sepsisLayout()),
        initialData: <String, dynamic>{
          'q': <String, dynamic>{'rr': true},
        },
      );

      // qSOFA totals 1, SIRS totals 0 — and "Scoring Systems", which merely
      // contains them, totals nothing at all. Before this, it grew a Σ 1 that
      // the paper form never prints.
      expect(_chip('Σ 1'), findsOneWidget);
      expect(_chip('Σ 0'), findsOneWidget);
      expect(_chip('Σ 2'), findsNothing);
    });

    testWidgets('showSectionTotal puts the chip back on the outer box',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _sepsisLayout(
            outerOmf: <String, dynamic>{'showSectionTotal': true},
          ),
        ),
        initialData: <String, dynamic>{
          'q': <String, dynamic>{'rr': true},
          's': <String, dynamic>{'temp': true},
        },
      );

      // The outer box now totals its parts: 1 + 1.
      expect(_chip('Σ 2'), findsOneWidget);
      expect(_chip('Σ 1'), findsNWidgets(2));
    });

    testWidgets('hideSectionTotal removes a chip that would otherwise show',
        (tester) async {
      await pumpForm(
        tester,
        definition: definitionOf(
          dataSchema: _schema,
          layout: _sepsisLayout(
            qsofaOmf: <String, dynamic>{'hideSectionTotal': true},
          ),
        ),
        initialData: <String, dynamic>{
          'q': <String, dynamic>{'rr': true},
        },
      );

      expect(_chip('Σ 1'), findsNothing);
      expect(_chip('Σ 0'), findsOneWidget); // SIRS still draws its own
    });
  });
}
