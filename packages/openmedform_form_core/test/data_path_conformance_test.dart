/// Replays the `data_path` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

/// The fixtures encode a data path as either a dotted string or a segment list;
/// [toPathSegments] accepts both, so pass it through unchanged.
Object _path(Object? raw) => raw!;

Map<String, dynamic>? _object(Object? raw) =>
    raw == null ? null : Map<String, dynamic>.from(raw as Map);

void main() {
  runConformanceModule('data_path', {
    'toPathSegments': (args) => toPathSegments(_path(args[0])),
    'getValueAtPath': (args) => getValueAtPath(args[0], _path(args[1])),
    'setValueAtPath': (args) =>
        setValueAtPath(_object(args[0]), _path(args[1]), args[2]),
    'deleteValueAtPath': (args) =>
        deleteValueAtPath(_object(args[0]), _path(args[1])),
    'getValueAtScope': (args) => getValueAtScope(args[0], args[1]! as String),
    'setValueAtScope': (args) =>
        setValueAtScope(_object(args[0]), args[1]! as String, args[2]),
  });

  // Behaviour the fixtures do not reach, because the TypeScript tests do not
  // either — but which the record table depends on from M5 (#6) onward.
  group('data_path beyond the fixtures', () {
    test('reads through a list by numeric index', () {
      final data = <String, dynamic>{
        'treatments': <dynamic>[
          <String, dynamic>{'date': '2026-08-01'},
          <String, dynamic>{'date': '2026-08-02'},
        ],
      };

      expect(getValueAtPath(data, 'treatments.1.date'), '2026-08-02');
    });

    test('an out-of-range or non-numeric list index reads as null', () {
      final data = <String, dynamic>{
        'treatments': <dynamic>[
          <String, dynamic>{'date': '2026-08-01'},
        ],
      };

      expect(getValueAtPath(data, 'treatments.7.date'), isNull);
      expect(getValueAtPath(data, 'treatments.date'), isNull);
    });

    test('writes do not mutate the input', () {
      final original = <String, dynamic>{
        'assessment': <String, dynamic>{'spo2': 88},
      };

      final updated = setValueAtPath(original, 'assessment.spo2', 95);

      expect(updated['assessment'], containsPair('spo2', 95));
      expect(
        original['assessment'],
        containsPair('spo2', 88),
        reason: 'setValueAtPath must leave the input untouched — the renderer '
            'relies on value identity to detect changes',
      );
      expect(identical(original['assessment'], updated['assessment']), isFalse);
    });

    test('untouched subtrees are shared rather than copied', () {
      final untouched = <String, dynamic>{'a': 1};
      final original = <String, dynamic>{
        'keep': untouched,
        'edit': <String, dynamic>{'b': 1},
      };

      final updated = setValueAtPath(original, 'edit.b', 2);

      expect(
        identical(updated['keep'], untouched),
        isTrue,
        reason: 'copy-on-write should clone only along the changed path',
      );
    });

    test('deleting removes the key rather than nulling it', () {
      final original = <String, dynamic>{
        'row': <String, dynamic>{'a': true, 'b': true},
      };

      final updated = deleteValueAtPath(original, 'row.a');
      final row = updated['row'] as Map<String, dynamic>;

      expect(row.containsKey('a'), isFalse);
      expect(row, containsPair('b', true));
    });

    test('writes into a list element without destroying the list', () {
      // The TypeScript's plain-object check excludes arrays, so it would
      // replace the whole list with a map here — silently discarding every
      // other record. Record-table cells write through exactly this shape.
      final original = <String, dynamic>{
        'treatments': <dynamic>[
          <String, dynamic>{'nurse': 'A'},
          <String, dynamic>{'nurse': 'B'},
        ],
      };

      final updated = setValueAtPath(original, 'treatments.1.nurse', 'C');
      final records = updated['treatments'] as List<Object?>;

      expect(records, hasLength(2));
      expect((records[0]! as Map<String, dynamic>)['nurse'], 'A');
      expect((records[1]! as Map<String, dynamic>)['nurse'], 'C');
      expect(
        (original['treatments']! as List<Object?>)[1],
        containsPair('nurse', 'B'),
        reason: 'the input must not be mutated',
      );
    });

    test('deleting a list element removes it and shifts the rest', () {
      final original = <String, dynamic>{
        'treatments': <dynamic>['a', 'b', 'c'],
      };

      final updated = deleteValueAtPath(original, 'treatments.1');

      expect(updated['treatments'], <dynamic>['a', 'c']);
      expect(original['treatments'], hasLength(3));
    });

    test('an out-of-range delete leaves the list alone', () {
      final original = <String, dynamic>{
        'treatments': <dynamic>['a'],
      };

      expect(deleteValueAtPath(original, 'treatments.7')['treatments'],
          <dynamic>['a']);
    });
  });
}
