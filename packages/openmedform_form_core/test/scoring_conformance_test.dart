/// Replays the `scoring` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

Map<String, dynamic> _map(Object? raw) =>
    Map<String, dynamic>.from(raw! as Map);

List<ScoreItem> _items(Object? raw) => (raw! as List)
    .map((item) => _map(item))
    .map(
      (item) => ScoreItem(
        scope: item['scope'] as String,
        path: item['path'] as String,
        points: item['points'] as num,
        section: item['section'] as String?,
      ),
    )
    .toList();

List<RiskBand>? _bands(Object? raw) => raw == null
    ? null
    : (raw as List).map((band) => RiskBand.fromJson(_map(band))).toList();

void main() {
  runConformanceModule('scoring', {
    'collectScoreItems': (args) =>
        collectScoreItems(_map(args[0])).map((item) => item.toJson()).toList(),
    'computeScore': (args) => computeScore(
          _items(args[0]),
          args[1],
          args.length > 2 ? _bands(args[2]) : null,
        ).toJson(),
    'scoreUiSchema': (args) => scoreUiSchema(
          _map(args[0]),
          args[1],
          args.length > 2 ? _bands(args[2]) : null,
        ).toJson(),
    'stratify': (args) => stratify(args[0]! as num, _bands(args[1]))?.toJson(),
  });

  group('isPresent', () {
    test('accepts exactly the documented set', () {
      for (final value in <Object?>[true, 1, 1.0, '1', 'yes', 7, 0.5]) {
        expect(isPresent(value), isTrue, reason: '$value should count');
      }
    });

    test('rejects near-misses, including uppercase YES', () {
      for (final value in <Object?>[
        false,
        0,
        -1,
        'YES',
        'Yes',
        'no',
        '',
        null,
        'true',
      ]) {
        expect(isPresent(value), isFalse, reason: '$value should not count');
      }
    });
  });
}
