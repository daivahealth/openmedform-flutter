/// Replays the `registry` conformance fixtures against the Dart port.
///
/// These cases carry `element` and `context` alongside `args`, because a tester
/// is built from `args` and *then* applied — so this module drives the fixture
/// directly rather than through [runConformanceModule].
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

ControlTester _tester(String name, List<Object?> args) {
  final argument = args[0]! as String;
  switch (name) {
    case 'byOmfControl':
      return byOmfControl(argument);
    case 'byOmfLayout':
      return byOmfLayout(argument);
    case 'byType':
      return byType(argument);
    case 'bySchemaType':
      return bySchemaType(argument);
    default:
      fail('no Dart tester factory registered for $name');
  }
}

ControlContext? _context(Object? raw) {
  if (raw == null) return null;
  final map = Map<String, dynamic>.from(raw as Map);
  final fieldSchema = map['fieldSchema'];
  final dataSchema = map['dataSchema'];
  return ControlContext(
    fieldSchema:
        fieldSchema is Map ? Map<String, dynamic>.from(fieldSchema) : null,
    dataSchema:
        dataSchema is Map ? Map<String, dynamic>.from(dataSchema) : null,
  );
}

void main() {
  final fixture = loadFixture('registry');

  group(
      'registry conformance (form-core '
      '${fixture.sourceCommit.substring(0, 7)})', () {
    test('the sentinel matches upstream', () {
      expect(notApplicable, fixture.raw['notApplicable']);
    });

    test('the empty-cell glyph matches upstream', () {
      expect(emptyCell, fixture.raw['emptyCell']);
    });

    for (final testCase in fixture.cases) {
      test(testCase.name, () {
        final tester = _tester(testCase.fn, testCase.args);
        final element = Map<String, dynamic>.from(
          decodeUndefined(testCase.raw['element'])! as Map,
        );
        final context = _context(decodeUndefined(testCase.raw['context']));

        expect(tester(element, context), testCase.expected);
      });
    }
  });

  group('registry resolution', () {
    test('the highest rank wins regardless of registration order', () {
      final registry = ControlRegistry<String>()
        ..register(byType('Control'), 'generic')
        ..register(byOmfControl('recordTable'), 'recordTable');

      final element = <String, dynamic>{
        'type': 'Control',
        'options': <String, dynamic>{
          'omf': <String, dynamic>{'control': 'recordTable'},
        },
      };

      expect(registry.resolve(element), 'recordTable');

      final reversed = ControlRegistry<String>()
        ..register(byOmfControl('recordTable'), 'recordTable')
        ..register(byType('Control'), 'generic');

      expect(reversed.resolve(element), 'recordTable');
    });

    test('an unmatched element resolves to null so the caller can fail loudly',
        () {
      final registry = ControlRegistry<String>()
        ..register(byOmfControl('recordTable'), 'recordTable');

      expect(registry.resolve(<String, dynamic>{'type': 'Group'}), isNull);
    });

    test('ties go to the entry registered first', () {
      final registry = ControlRegistry<String>()
        ..register(byType('Group'), 'first')
        ..register(byType('Group'), 'second');

      expect(registry.resolve(<String, dynamic>{'type': 'Group'}), 'first');
    });
  });
}
