/// Shared harness for replaying the conformance fixtures.
///
/// Each fixture case names a function, its arguments, and the value the
/// TypeScript implementation produced. A module test supplies a dispatch table
/// from function name to a Dart closure; this harness does the rest.
///
/// The comparison rules it implements are the ones in docs/CONFORMANCE.md, and they
/// exist because a literal `==` would report differences that are artefacts of
/// crossing languages rather than real divergence.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Stands in for JavaScript `undefined`, which JSON cannot represent.
///
/// Dart distinguishes an absent key from a null one, and so does the code being
/// ported — `readRecordPath({}, 'a.b')` returning `undefined` is a different
/// assertion from returning `null`. The generator writes this marker; we decode
/// it back to [undefinedValue].
const undefinedMarker = '__undefined__';

/// The Dart stand-in for `undefined`. Dart has one absent value, so `undefined`
/// and `null` both land here; the marker keeps the *fixture* unambiguous even
/// though the runtime value cannot be.
const Object? undefinedValue = null;

/// A function under test: takes the decoded argument list, returns any value.
typedef ConformanceFn = Object? Function(List<Object?> args);

class ConformanceCase {
  ConformanceCase({
    required this.name,
    required this.fn,
    required this.args,
    required this.expected,
    required this.raw,
  });

  final String name;
  final String fn;
  final List<Object?> args;
  final Object? expected;

  /// The undecoded case, for modules with extra fields (registry, say).
  final Map<String, dynamic> raw;
}

class ConformanceFixture {
  ConformanceFixture({
    required this.module,
    required this.sourceCommit,
    required this.cases,
    required this.raw,
  });

  final String module;
  final String sourceCommit;
  final List<ConformanceCase> cases;
  final Map<String, dynamic> raw;
}

/// Load `test/conformance/<module>.json`.
ConformanceFixture loadFixture(String module) {
  final file = File('test/conformance/$module.json');
  if (!file.existsSync()) {
    throw StateError(
      'Missing fixture ${file.path}. Regenerate with tool/conformance_export.ts '
      '— see docs/CONFORMANCE.md.',
    );
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final cases = (json['cases'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(
        (c) => ConformanceCase(
          name: c['name'] as String,
          fn: c['fn'] as String,
          args: (decodeUndefined(c['args']) as List<Object?>?) ?? const [],
          expected: decodeUndefined(c['expected']),
          raw: c,
        ),
      )
      .toList();

  return ConformanceFixture(
    module: json['module'] as String,
    sourceCommit: json['sourceCommit'] as String,
    cases: cases,
    raw: json,
  );
}

/// Load one of the golden form documents.
Map<String, dynamic> loadGolden(String name) {
  final file = File('test/conformance/golden/$name');
  if (!file.existsSync()) {
    throw StateError('Missing golden document ${file.path}.');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Replace every [undefinedMarker] with [undefinedValue], recursively.
Object? decodeUndefined(Object? value) {
  if (value is String) return value == undefinedMarker ? undefinedValue : value;
  if (value is List) return value.map(decodeUndefined).toList();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: decodeUndefined(entry.value),
    };
  }
  return value;
}

/// Structural equality with the cross-language allowances from docs/CONFORMANCE.md.
///
/// Numbers widen to [num] before comparing: JavaScript has only `double`, so a
/// value that is `1` in Dart may arrive as `1.0`, and vice versa. Nothing else
/// is loosened — key sets must match exactly, so a Dart port that seeds a field
/// the TypeScript leaves absent still fails.
bool conformanceEquals(Object? actual, Object? expected) {
  if (actual is num && expected is num) {
    if (actual.isNaN && expected.isNaN) return true;
    return actual.toDouble() == expected.toDouble();
  }

  if (actual is List && expected is List) {
    if (actual.length != expected.length) return false;
    for (var i = 0; i < actual.length; i++) {
      if (!conformanceEquals(actual[i], expected[i])) return false;
    }
    return true;
  }

  if (actual is Map && expected is Map) {
    final actualKeys = actual.keys.map((k) => k.toString()).toSet();
    final expectedKeys = expected.keys.map((k) => k.toString()).toSet();
    if (actualKeys.length != expectedKeys.length ||
        !actualKeys.containsAll(expectedKeys)) {
      return false;
    }
    for (final key in expectedKeys) {
      if (!conformanceEquals(actual[key], expected[key])) return false;
    }
    return true;
  }

  return actual == expected;
}

/// A [Matcher] wrapping [conformanceEquals], for readable failure output.
Matcher conformsTo(Object? expected) => _ConformanceMatcher(expected);

class _ConformanceMatcher extends Matcher {
  const _ConformanceMatcher(this._expected);

  final Object? _expected;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      conformanceEquals(item, _expected);

  @override
  Description describe(Description description) => description
      .add('structurally equal to ')
      .addDescriptionOf(_expected)
      .add(' (numbers compared as num)');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatch,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) =>
      mismatch
          .add('was ')
          .addDescriptionOf(item)
          .add('\n  expected: ')
          .add(jsonEncode(_expected))
          .add('\n  actual:   ')
          .add(_safeEncode(item));

  static String _safeEncode(Object? value) {
    try {
      return jsonEncode(value);
    } on JsonUnsupportedObjectError {
      return value.toString();
    }
  }
}

/// Replay every case in [module] against [dispatch].
///
/// Every case in the fixture must be claimed by [dispatch] or listed in
/// [pending] — an unhandled function name fails rather than being quietly
/// skipped, so a module cannot look green while leaving part of its contract
/// unimplemented.
///
/// [pending] maps a function name to the reason it is not implemented yet. Its
/// cases are reported as skipped with that reason attached, which keeps
/// deferred work visible in the test output instead of invisible.
/// Narrows what is compared for one function, applied to **both** the actual
/// and the expected value.
///
/// Use this where part of a result is genuinely not portable across languages —
/// Ajv's error messages and `params`, for instance. Projecting states the
/// portable contract in code instead of deleting the case or letting it rot as
/// permanently skipped.
typedef ConformanceProjection = Object? Function(Object? value);

void runConformanceModule(
  String module,
  Map<String, ConformanceFn> dispatch, {
  Map<String, String> pending = const <String, String>{},
  Map<String, ConformanceProjection> project =
      const <String, ConformanceProjection>{},
}) {
  final fixture = loadFixture(module);

  group(
      '$module conformance (form-core ${fixture.sourceCommit.substring(0, 7)})',
      () {
    test('every fixture function is implemented or explicitly pending', () {
      final unaccounted = fixture.cases
          .map((c) => c.fn)
          .where((fn) => !dispatch.containsKey(fn) && !pending.containsKey(fn))
          .toSet();
      expect(
        unaccounted,
        isEmpty,
        reason: 'the $module fixture exercises functions with no Dart '
            'implementation and no pending note: ${unaccounted.join(', ')}',
      );
    });

    for (final testCase in fixture.cases) {
      final deferred = pending[testCase.fn];

      final projection = project[testCase.fn];

      test(
        testCase.name,
        () {
          final fn = dispatch[testCase.fn];
          if (fn == null) {
            fail('no Dart implementation registered for ${testCase.fn}');
          }

          final actual = fn(testCase.args);
          if (projection == null) {
            expect(actual, conformsTo(testCase.expected));
          } else {
            expect(
              projection(actual),
              conformsTo(projection(testCase.expected)),
            );
          }
        },
        skip: deferred == null ? null : '${testCase.fn}: $deferred',
      );
    }
  });
}
