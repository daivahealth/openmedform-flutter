@Tags(<String>['golden'])

/// Pixel goldens, at both breakpoints.
///
/// Tagged so CI can exclude them: golden images rasterise differently on macOS
/// and Linux, and a suite that fails on the runner's platform rather than on a
/// real regression teaches everyone to ignore it. These are generated and
/// checked on macOS.
///
/// Run with `flutter test --tags golden`; update with
/// `flutter test --tags golden --update-goldens`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

import 'support/golden_fonts.dart';
import 'support/harness.dart';

const _schema = <String, dynamic>{
  'type': 'object',
  'properties': <String, dynamic>{
    'callDetails': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'date': <String, dynamic>{
          'type': 'string',
          'format': 'date',
          'title': 'Date',
        },
        'ward': <String, dynamic>{'type': 'string', 'title': 'Ward'},
      },
      'required': <String>['date'],
    },
    'assessment': <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'spo2': <String, dynamic>{'type': 'integer', 'title': 'SpO2'},
        'avpu': <String, dynamic>{
          'type': 'string',
          'title': 'AVPU',
          'enum': <String>['ALERT', 'VOICE', 'PAIN', 'UNRESPONSIVE'],
        },
        'sepsis': <String, dynamic>{'type': 'boolean', 'title': 'Sepsis'},
        'anticoagulant': <String, dynamic>{
          'type': 'string',
          'title': 'On anticoagulants',
          'enum': <String>['YES', 'NO'],
        },
        'handover': <String, dynamic>{'type': 'string', 'title': 'Handover'},
      },
    },
    'total': <String, dynamic>{'type': 'number'},
  },
};

const _layout = <String, dynamic>{
  'type': 'VerticalLayout',
  'elements': <dynamic>[
    <String, dynamic>{
      'type': 'Label',
      'text': 'Complete every section.\nEscalate immediately if SpO2 < 92.',
    },
    <String, dynamic>{
      'type': 'Group',
      'label': 'Call details',
      'options': <String, dynamic>{
        'omf': <String, dynamic>{'accentColor': '#4a2d5c', 'icon': '📞'},
      },
      'elements': <dynamic>[
        <String, dynamic>{
          'type': 'HorizontalLayout',
          'elements': <dynamic>[
            <String, dynamic>{
              'type': 'Control',
              'scope': '#/properties/callDetails/properties/date',
              'options': <String, dynamic>{
                'omf': <String, dynamic>{
                  'screen': <String, dynamic>{'colSpan': 4},
                },
              },
            },
            <String, dynamic>{
              'type': 'Control',
              'scope': '#/properties/callDetails/properties/ward',
              'options': <String, dynamic>{
                'omf': <String, dynamic>{
                  'screen': <String, dynamic>{'colSpan': 8},
                },
              },
            },
          ],
        },
      ],
    },
    <String, dynamic>{
      'type': 'Group',
      'label': 'Assessment',
      'options': <String, dynamic>{
        'omf': <String, dynamic>{
          'pointLegend': <int>[1, 3, 5],
        },
      },
      'elements': <dynamic>[
        <String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/assessment/properties/spo2',
        },
        <String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/assessment/properties/avpu',
        },
        <String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/assessment/properties/anticoagulant',
          'options': <String, dynamic>{
            'omf': <String, dynamic>{'control': 'radio'},
          },
        },
        <String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/assessment/properties/handover',
          'options': <String, dynamic>{
            'omf': <String, dynamic>{
              'control': 'textarea',
              'screen': <String, dynamic>{'rows': 2},
            },
          },
        },
        <String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/assessment/properties/sepsis',
          'options': <String, dynamic>{
            'omf': <String, dynamic>{'points': 3},
          },
        },
      ],
    },
    <String, dynamic>{
      'type': 'Control',
      'scope': '#/properties/total',
      'label': 'Total Score',
      'options': <String, dynamic>{
        'omf': <String, dynamic>{
          'control': 'scoreSummary',
          'bands': <dynamic>[
            <String, dynamic>{
              'maxScore': 2,
              'label': 'Low',
              'color': '#1e8e5a'
            },
            <String, dynamic>{
              'minScore': 3,
              'label': 'High',
              'color': '#c0392b',
            },
          ],
        },
      },
    },
  ],
};

const _data = <String, dynamic>{
  'callDetails': <String, dynamic>{'date': '2026-07-24', 'ward': 'ICU 3'},
  'assessment': <String, dynamic>{
    'spo2': 88,
    'avpu': 'VOICE',
    'sepsis': true,
    'anticoagulant': 'YES',
    'handover': 'Deteriorating overnight; review requested.',
  },
};

Widget _app({required Widget child}) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        extensions: const <ThemeExtension<dynamic>>[
          OmfTheme(fontFamily: 'Roboto'),
        ],
      ),
      home: Scaffold(backgroundColor: Colors.white, body: child),
    );

void main() {
  setUpAll(loadGoldenFonts);

  Future<void> pumpAt(WidgetTester tester, Size size,
      {bool readOnly = false}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(
        child: OmfFormRenderer(
          definition: definitionOf(dataSchema: _schema, layout: _layout),
          initialData: _data,
          readOnly: readOnly,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide — above the 640px breakpoint', (tester) async {
    // Horizontal layouts stay in a row, honouring colSpan 4/8.
    await pumpAt(tester, const Size(900, 900));
    await expectLater(
      find.byType(OmfFormRenderer),
      matchesGoldenFile('goldens/form_wide.png'),
    );
  });

  testWidgets('narrow — below the 640px breakpoint', (tester) async {
    // The same form must stack rather than squeeze, matching what the web
    // renderer does when its container narrows.
    await pumpAt(tester, const Size(420, 1100));
    await expectLater(
      find.byType(OmfFormRenderer),
      matchesGoldenFile('goldens/form_narrow.png'),
    );
  });

  testWidgets('read-only replay', (tester) async {
    await pumpAt(tester, const Size(900, 900), readOnly: true);
    await expectLater(
      find.byType(OmfFormRenderer),
      matchesGoldenFile('goldens/form_readonly.png'),
    );
  });
}
