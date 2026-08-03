/// Replays the `record_table` conformance fixtures against the Dart port.
library;

import 'package:openmedform_form_core/openmedform_form_core.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

Map<String, dynamic>? _map(Object? raw) =>
    raw == null ? null : Map<String, dynamic>.from(raw as Map);

RecordTableColumn _column(Object? raw) =>
    RecordTableColumn.fromJson(_map(raw)!);

List<RecordTableColumn> _columns(Object? raw) =>
    (raw! as List).map(_column).toList();

void main() {
  runConformanceModule('record_table', {
    'readRecordPath': (args) => readRecordPath(args[0], args[1] as String?),
    'recordCellText': (args) => recordCellText(args[0], _column(args[1])),
    'recordCountText': (args) =>
        recordCountText(args[0] as String?, (args[1]! as num).toInt()),
    'createRecordDefault': (args) => createRecordDefault(_map(args[0])),
    'deriveRecordColumns': (args) => deriveRecordColumns(
          _map(args[0]),
          args.length > 1 && args[1] != null ? (args[1]! as num).toInt() : 4,
        ).map((column) => column.toJson()).toList(),
    'isColumnEditable': (args) => isColumnEditable(_column(args[0])),
    'fieldsOutsideColumns': (args) =>
        fieldsOutsideColumns(_map(args[0]), _columns(args[1])),
  });

  group('record table beyond the fixtures', () {
    test('a whole double prints like JavaScript, without a decimal point', () {
      // JSON round-tripping can hand us 2.0 where the web renderer sees 2.
      // Printing "2.0" in a dose column would be a visible divergence.
      expect(
        recordCellText(
          <String, dynamic>{'dose': 2.0},
          const RecordTableColumn(label: 'Dose', path: 'dose'),
        ),
        '2',
      );
      expect(
        recordCellText(
          <String, dynamic>{'dose': 2.5},
          const RecordTableColumn(label: 'Dose', path: 'dose'),
        ),
        '2.5',
      );
    });

    test('reads a path that crosses a list', () {
      final record = <String, dynamic>{
        'rounds': <dynamic>[
          <String, dynamic>{'nurse': 'A'},
          <String, dynamic>{'nurse': 'B'},
        ],
      };

      expect(readRecordPath(record, 'rounds.1.nurse'), 'B');
    });
  });
}
