/// Replays the `enum_options` conformance fixtures against the Dart port.
///
/// The comparison surface is `EnumOption.toJson()` — `code`, `label` and the
/// points a choice carries. `EnumOption.value` deliberately keeps the code's
/// JSON type, which is a documented divergence rather than part of the
/// contract; see docs/CONFORMANCE.md.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

Map<String, dynamic>? _map(Object? raw) =>
    raw == null ? null : Map<String, dynamic>.from(raw as Map);

List<Map<String, dynamic>> _json(List<EnumOption> options) =>
    options.map((option) => option.toJson()).toList();

void main() {
  runConformanceModule('enum_options', {
    'resolveEnumOptions': (args) =>
        _json(resolveEnumOptions(_map(args[0]), _map(args[1]))),
    'resolveMultiEnumOptions': (args) =>
        _json(resolveMultiEnumOptions(_map(args[0]), _map(args[1]))),
    'elementOptionPoints': (args) => elementOptionPoints(_map(args[0])),
  });

  group('divergences the fixtures cannot state', () {
    test('the stored value keeps its JSON type', () {
      // Upstream stores `String(const)`, so a numeric enum is submitted as a
      // string there and fails `type: integer` on the way back in. `code` still
      // matches upstream, so scoring and the fixtures agree.
      final option = resolveEnumOptions(<String, dynamic>{
        'enum': <Object?>[1, 2],
      }, null)
          .first;

      expect(option.value, 1);
      expect(option.code, '1');
    });

    test('anyOf is accepted on the same terms as oneOf', () {
      final options = resolveEnumOptions(<String, dynamic>{
        'anyOf': <Object?>[
          <String, dynamic>{'const': 'A', 'title': 'Alpha'},
        ],
      }, null);

      expect(options.single.label, 'Alpha');
    });

    test('a mixed combinator is a constraint, not a picker', () {
      // Upstream filters the non-const branches out and returns what is left.
      // A `oneOf` is also a validation construct, and rendering a radio for one
      // puts a control in front of a clinician that the form never meant.
      final options = resolveEnumOptions(<String, dynamic>{
        'oneOf': <Object?>[
          <String, dynamic>{'const': 'A', 'title': 'Alpha'},
          <String, dynamic>{'minLength': 3},
        ],
      }, null);

      expect(options, isEmpty);
    });
  });
}
