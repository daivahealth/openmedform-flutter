/// Label resolution.
///
/// There is no conformance fixture for this module: `controlLabel` lives in the
/// print engine and is private to `render-html.ts`, so it is not reachable from
/// the form-core export the generator drives. These cases are transliterated
/// from that source directly, and the divergence table in `schema/labels.dart`
/// records why the humanisation rules differ across the platform.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

void main() {
  group('labelFromKey', () {
    test('splits a camelCase boundary and capitalises the first character', () {
      expect(labelFromKey('insertedBy'), 'Inserted By');
      expect(labelFromKey('situation'), 'Situation');
    });

    test('leaves a digit-to-upper boundary unsplit', () {
      // The print engine's boundary regex is ([a-z])([A-Z]) — no digits — so
      // this differs from humanizeRecordKey on the same input.
      expect(labelFromKey('spo2Reading'), 'Spo2Reading');
      expect(humanizeRecordKey('spo2Reading'), 'Spo2 reading');
    });

    test('an empty key stays empty rather than throwing', () {
      expect(labelFromKey(''), '');
    });
  });

  group('controlLabel', () {
    const fieldSchema = <String, dynamic>{'title': 'Ημ/νία'};

    test('an explicit string label wins', () {
      expect(
        controlLabel(
          <String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/callDetails/properties/date',
            'label': 'Explicit',
          },
          fieldSchema: fieldSchema,
        ),
        'Explicit',
      );
    });

    test('falls back to the field schema title', () {
      // The golden form is Greek and leans on `title` precisely so humanised
      // English keys never reach a clinician.
      expect(
        controlLabel(
          <String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/callDetails/properties/date',
          },
          fieldSchema: fieldSchema,
        ),
        'Ημ/νία',
      );
    });

    test('an empty title falls through to the humanised key', () {
      expect(
        controlLabel(
          <String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/callDetails/properties/floorRoom',
          },
          fieldSchema: const <String, dynamic>{'title': ''},
        ),
        'Floor Room',
      );
    });

    test('falls back to the humanised last scope segment', () {
      expect(
        controlLabel(<String, dynamic>{
          'type': 'Control',
          'scope': '#/properties/callDetails/properties/floorRoom',
        }),
        'Floor Room',
      );
    });

    test('a non-string label is not treated as a label', () {
      // JSON Forms allows `label: false` to suppress a label; it is not a
      // display string, so the chain must continue past it.
      expect(
        controlLabel(
          <String, dynamic>{
            'type': 'Control',
            'scope': '#/properties/situation',
            'label': false,
          },
          fieldSchema: const <String, dynamic>{'title': 'Κατάσταση'},
        ),
        'Κατάσταση',
      );
    });
  });
}
