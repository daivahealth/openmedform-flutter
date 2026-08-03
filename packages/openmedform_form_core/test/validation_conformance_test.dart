/// Replays the `validation` conformance fixtures against the Dart validator.
///
/// The contract is deliberately not "reproduce Ajv exactly", because no Dart
/// validator does. It is three claims, in descending order of how much they
/// matter clinically:
///
/// 1. **`valid` matches Ajv on every case.** This is the one that decides
///    whether a clinician is stopped from submitting, so it is exact.
/// 2. **Every instance path Ajv flags is also flagged here.** No field that the
///    server will reject may go unhighlighted.
/// 3. **Keywords are best-effort.** The package exposes no keyword field, so it
///    is recovered from diagnostics and used only to choose a friendly message.
///
/// Extra, more specific paths are allowed and asserted to be *more* precise —
/// see the `required` case below. docs/CONFORMANCE.md records the reasoning.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

void main() {
  final fixture = loadFixture('validation');
  final validator = JsonSchemaValidator();

  group(
      'validation conformance (form-core '
      '${fixture.sourceCommit.substring(0, 7)})', () {
    for (final testCase in fixture.cases) {
      final schema = Map<String, dynamic>.from(testCase.args[0]! as Map);
      final data = testCase.args[1];
      final expected = Map<String, dynamic>.from(testCase.expected! as Map);
      final expectedErrors =
          (expected['errors'] as List<Object?>).cast<Map<Object?, Object?>>();

      test('${testCase.name} — verdict', () {
        expect(
          validator.validate(schema, data).valid,
          expected['valid'],
          reason: 'the verdict decides whether a submit is blocked, so it must '
              'match Ajv exactly',
        );
      });

      if (expectedErrors.isEmpty) continue;

      test('${testCase.name} — flags every path Ajv flags', () {
        final actual = validator
            .validate(schema, data)
            .errors
            .map((error) => error.instancePath)
            .toSet();
        final wanted = expectedErrors
            .map((error) => error['instancePath'] as String)
            .toSet();

        expect(
          wanted.difference(actual),
          isEmpty,
          reason: 'a field the server will reject would go unhighlighted',
        );
      });
    }
  });

  group('documented divergences from Ajv', () {
    test('required also points at the missing property, not just its parent',
        () {
      final result = validator.validate(
        <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{'a': <String, dynamic>{}},
          'required': <String>['a'],
        },
        <String, dynamic>{},
      );

      final paths = result.errors.map((e) => e.instancePath).toSet();
      expect(paths, contains(''), reason: 'Ajv reports the containing object');
      expect(
        paths,
        contains('/a'),
        reason: 'this validator additionally names the missing property, which '
            'is better for field highlighting rather than a defect',
      );
    });

    test('a nested if/then is reported as the enclosing allOf', () {
      // Ajv reports `if` and `required`; this reports `allOf`. Both mark the
      // root as invalid, so the verdict and the flagged path agree — only the
      // keyword differs, and the keyword only picks a message.
      final golden = loadGolden('rrt-sbar.definition.json');
      final result = validator.validate(
        Map<String, dynamic>.from(golden['dataSchema'] as Map),
        <String, dynamic>{
          'callDetails': <String, dynamic>{'date': '2026-07-24'},
          'assessment': <String, dynamic>{'spo2': 88},
        },
      );

      expect(result.valid, isFalse);
      expect(result.errors.map((e) => e.keyword), contains('allOf'));
    });
  });

  group('validator behaviour', () {
    test('formats are asserted, which 2020-12 does not do by default', () {
      const schema = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'd': <String, dynamic>{'type': 'string', 'format': 'date'},
        },
      };

      expect(
        validator.validate(schema, <String, dynamic>{'d': 'not-a-date'}).valid,
        isFalse,
        reason: 'ajv-formats asserts formats upstream, so this must too',
      );
      expect(
        validator.validate(schema, <String, dynamic>{'d': '2026-08-01'}).valid,
        isTrue,
      );
    });

    test('an uncompilable schema reports rather than throwing', () {
      // An authoring bug must not crash a form a clinician is filling in.
      final result = validator.validate(
        <String, dynamic>{r'$ref': 'https://example.invalid/nope.json'},
        <String, dynamic>{},
      );

      expect(result.valid, isFalse);
      expect(result.errors.single.keyword, 'schema');
    });

    test('compiled schemas are cached across calls', () {
      const schema = <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'a': <String, dynamic>{'type': 'integer'},
        },
      };

      // Same map instance twice: the second call must reuse the compilation.
      // Correctness is what is observable here; the cache is a performance
      // guard for rules, which re-validate on every rebuild.
      expect(
          validator.validate(schema, <String, dynamic>{'a': 1}).valid, isTrue);
      expect(
        validator.validate(schema, <String, dynamic>{'a': 'x'}).valid,
        isFalse,
      );
    });

    test('errorsAt selects the errors for one field', () {
      final result = validator.validate(
        <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'a': <String, dynamic>{'type': 'integer', 'maximum': 5},
          },
        },
        <String, dynamic>{'a': 9},
      );

      expect(result.errorsAt('/a'), isNotEmpty);
      expect(result.errorsAt('/b'), isEmpty);
    });
  });
}
