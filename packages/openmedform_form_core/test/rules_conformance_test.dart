/// Replays the `rules` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

Map<String, dynamic> _map(Object? raw) =>
    Map<String, dynamic>.from(raw! as Map);

List<Map<String, dynamic>>? _maps(Object? raw) =>
    raw == null ? null : (raw as List).map(_map).toList();

void main() {
  final validator = JsonSchemaValidator();

  runConformanceModule('rules', {
    'evaluateCondition': (args) =>
        evaluateCondition(_map(args[0]), args[1], validator),
    'evaluateRule': (args) =>
        evaluateRule(_map(args[0]), args[1], validator).toJson(),
    'evaluateElementState': (args) =>
        evaluateElementState(_map(args[0]), args[1], validator).toJson(),
    'filterVisibleElements': (args) => filterVisibleElements(
          _maps(args[0]),
          args[1],
          validator,
          parentEnabled: args.length > 2 ? args[2]! as bool : true,
        ).map((visible) => visible.toJson()).toList(),
    'hasElementRules': (args) => hasElementRules(_maps(args[0])),
  });

  group('rules beyond the fixtures', () {
    test('an unknown effect leaves the element visible and enabled', () {
      // Forward compatibility: a form authored against a newer vocabulary must
      // degrade to showing the field, never to silently hiding it.
      final state = evaluateRule(
        <String, dynamic>{
          'effect': 'TELEPORT',
          'condition': <String, dynamic>{'scope': '#/properties/situation'},
        },
        <String, dynamic>{'situation': 'text'},
        validator,
      );

      expect(state, ElementState.visibleEnabled);
    });

    test('a malformed rule does not hide the field', () {
      expect(
        evaluateRule(<String, dynamic>{}, <String, dynamic>{}, validator),
        ElementState.visibleEnabled,
      );
      expect(
        evaluateElementState(
          <String, dynamic>{'rule': 'nonsense'},
          <String, dynamic>{},
          validator,
        ),
        ElementState.visibleEnabled,
      );
    });

    test('presence treats false and zero as answered', () {
      const condition = <String, dynamic>{'scope': '#/properties/situation'};

      // A clinician who answered "no" has answered. Treating false as absent
      // would collapse a recorded negative into an unfilled field.
      expect(
        evaluateCondition(
            condition, <String, dynamic>{'situation': false}, validator),
        isTrue,
      );
      expect(
        evaluateCondition(
            condition, <String, dynamic>{'situation': 0}, validator),
        isTrue,
      );
      expect(
        evaluateCondition(
            condition, <String, dynamic>{'situation': ''}, validator),
        isFalse,
      );
      expect(
        evaluateCondition(condition, <String, dynamic>{}, validator),
        isFalse,
      );
    });
  });
}
