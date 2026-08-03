/// Guards the conformance fixtures themselves.
///
/// The fixtures are the parity gate for the whole port: every later phase
/// asserts Dart behaviour against them. Before any module exists there is still
/// something worth checking — that the fixtures are present, parseable, pinned
/// to a single upstream commit, and shaped the way the Dart runners will expect.
///
/// A drifting or half-regenerated fixture set would otherwise show up much later
/// as a confusing module failure.
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// Modules that must have a fixture file. Mirrors docs/ARCHITECTURE.md section 10.
const _modules = <String>[
  'pointer',
  'data_path',
  'rules',
  'scoring',
  'record_table',
  'serialization',
  'validation',
  'i18n',
  'registry',
];

const _goldenFiles = <String>[
  'rrt-sbar.definition.json',
  'rrt-sbar.sample-empty.json',
  'rrt-sbar.sample-completed.json',
];

Directory get _conformanceDir {
  // `dart test` runs with the package root as cwd.
  final dir = Directory('test/conformance');
  if (!dir.existsSync()) {
    fail('Conformance fixtures missing at ${dir.absolute.path}. '
        'Regenerate them with tool/conformance_export.ts — see docs/CONFORMANCE.md.');
  }
  return dir;
}

Map<String, dynamic> _readJson(String relativePath) {
  final file = File('${_conformanceDir.path}/$relativePath');
  expect(file.existsSync(), isTrue, reason: 'missing fixture $relativePath');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('conformance fixtures', () {
    test('every module has a fixture file with at least one case', () {
      for (final module in _modules) {
        final fixture = _readJson('$module.json');
        expect(fixture['module'], module,
            reason: '$module.json declares the wrong module name');

        final cases = fixture['cases'] as List<dynamic>;
        expect(cases, isNotEmpty, reason: '$module.json has no cases');

        for (final entry in cases) {
          final testCase = entry as Map<String, dynamic>;
          expect(testCase['name'], isA<String>(),
              reason: 'a case in $module.json has no name');
          expect(testCase.containsKey('expected'), isTrue,
              reason: 'case "${testCase['name']}" in $module.json '
                  'has no expected value');
        }
      }
    });

    test('all fixtures are pinned to the same upstream commit', () {
      final commits = <String, String>{
        for (final module in _modules)
          module: _readJson('$module.json')['sourceCommit'] as String,
      };

      final distinct = commits.values.toSet();
      expect(distinct, hasLength(1),
          reason: 'fixtures were generated from different form-core commits, '
              'so they cannot be trusted as a single parity baseline: $commits');

      // A full SHA, not an abbreviation — docs/CONFORMANCE.md records the same value.
      expect(distinct.single, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('the golden form and its two sample datasets are present', () {
      for (final name in _goldenFiles) {
        final json = _readJson('golden/$name');
        expect(json, isNotEmpty, reason: 'golden/$name is empty');
      }

      final definition = _readJson('golden/rrt-sbar.definition.json');
      expect(definition['dataSchema'], isA<Map<String, dynamic>>());
      expect(definition['uiSchema'], isA<Map<String, dynamic>>());
    });

    test('validation cases carry only comparable error fields', () {
      // Ajv message text is validator-specific and deliberately excluded from
      // the contract; comparing it would guarantee a red suite in Dart.
      final cases = _readJson('validation.json')['cases'] as List<dynamic>;

      for (final entry in cases) {
        final expected =
            (entry as Map<String, dynamic>)['expected'] as Map<String, dynamic>;
        expect(expected['valid'], isA<bool>());

        for (final error in expected['errors'] as List<dynamic>) {
          expect(
            (error as Map<String, dynamic>).keys.toSet(),
            {'instancePath', 'keyword'},
            reason: 'validation fixtures must not encode Ajv message text',
          );
        }
      }
    });
  });
}
