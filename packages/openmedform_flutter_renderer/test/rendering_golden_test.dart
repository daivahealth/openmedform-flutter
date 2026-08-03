@Tags(<String>['golden'])

/// Pixel goldens.
///
/// Tagged so CI can exclude them: golden images are rasterised differently on
/// macOS and Linux, and a suite that fails on the runner's platform rather than
/// on a real regression teaches everyone to ignore it. These are generated and
/// checked on macOS for now; M7 (#8) pins a single platform for the full golden
/// suite across both breakpoints.
///
/// Run with `flutter test --tags golden`, update with
/// `flutter test --tags golden --update-goldens`.
///
/// Note that `flutter test` renders text with a placeholder font, so glyphs
/// appear as blocks. What this golden actually guards is structure: section
/// borders and accent colour, the 4/8 colSpan split, point-badge colours, and
/// the subtotal chip. Bundling a real font so text is verified too is part of
/// M7 (#8).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

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
      },
    },
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
          'pointLegend': <int>[1, 3, 5]
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
          'scope': '#/properties/assessment/properties/sepsis',
          'options': <String, dynamic>{
            'omf': <String, dynamic>{'points': 3},
          },
        },
      ],
    },
  ],
};

void main() {
  testWidgets('standard elements render to the reference image',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: OmfFormRenderer(
            definition: definitionOf(dataSchema: _schema, layout: _layout),
            initialData: const <String, dynamic>{
              'callDetails': <String, dynamic>{
                'date': '2026-07-24',
                'ward': 'ICU 3',
              },
              'assessment': <String, dynamic>{
                'spo2': 88,
                'avpu': 'VOICE',
                'sepsis': true,
              },
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(OmfFormRenderer),
      matchesGoldenFile('goldens/standard_elements.png'),
    );
  });
}
