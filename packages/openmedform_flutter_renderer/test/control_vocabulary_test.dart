/// Parity guard: the default registry must claim every canonical omf control.
///
/// The Dart twin of the web renderers' vocabulary tests
/// (`renderer-registry.test.ts`, `renderer-set.test.ts`). `omfControlNames` is
/// the contract between the AI builder — which may emit any of these names —
/// and every renderer, so a control added upstream and left unimplemented here
/// has to fail CI rather than wait to be noticed on a real form.
///
/// It is not hypothetical: `checkboxGroup` was added to the vocabulary and
/// reached this renderer with no registration of its own, where a mislabelled
/// element then rendered as an empty grid (#11).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:openmedform_flutter_renderer/openmedform_flutter_renderer.dart';

/// The rank `byOmfControl` hands out by default. A custom control must win at
/// least this, which is what separates "implemented" from "fell through to the
/// generic string box".
const int _customControlRank = 20;

void main() {
  final registry = createDefaultRegistry();

  // A plain string field, so the generic by-schema-type entry (rank 8) is a
  // genuine competitor. Asserting only that *something* matched would pass for
  // a name nobody had implemented.
  const context = ControlContext(
    dataSchema: <String, dynamic>{
      'type': 'object',
      'properties': <String, dynamic>{
        'x': <String, dynamic>{'type': 'string'},
      },
    },
    fieldSchema: <String, dynamic>{'type': 'string'},
  );

  group('the default registry covers the canonical omf.control vocabulary', () {
    for (final name in omfControlNames) {
      test('claims omf.control "$name"', () {
        final element = <String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/x',
          'options': <String, dynamic>{
            'omf': <String, dynamic>{'control': name},
          },
        };

        expect(
          registry.bestRank(element, context),
          greaterThanOrEqualTo(_customControlRank),
          reason: '"$name" is in omfControlNames but no control in '
              'createDefaultRegistry() claims it above the generic fallback, '
              'so it would silently render as a plain text box',
        );
      });
    }
  });

  group('the guard itself', () {
    test('a name outside the vocabulary is not claimed as a custom control',
        () {
      // Proves the assertion above can fail: an unimplemented control falls
      // through to the generic string entry at rank 8.
      final element = <String, dynamic>{
        'type': 'Control',
        'scope': '#/properties/x',
        'options': <String, dynamic>{
          'omf': <String, dynamic>{'control': 'notARealControl'},
        },
      };

      expect(
        registry.bestRank(element, context),
        lessThan(_customControlRank),
      );
    });

    test('the vocabulary is not silently empty', () {
      // A guard that iterates nothing passes forever.
      expect(omfControlNames, hasLength(12));
    });
  });
}
