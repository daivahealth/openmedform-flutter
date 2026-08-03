/// Pure logic behind the `recordTable` control — the repeating clinical
/// encounter log (treatment days, medication rounds, observation entries).
///
/// Ported from `packages/form-core/src/record-table/summary.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// This lives in the core rather than the renderer for the same reason it does
/// upstream: every renderer must derive a summary cell identically. A treatment
/// log showing a different date or adverse-event count in two places is a
/// clinical safety problem, not a cosmetic one.
library;

/// A summary column, as declared in `options.omf.recordTable`.
class RecordTableColumn {
  const RecordTableColumn({
    required this.label,
    this.path,
    this.countOf,
    this.pairWith,
    this.width,
    this.align,
  });

  factory RecordTableColumn.fromJson(Map<String, dynamic> json) =>
      RecordTableColumn(
        label: json['label'] as String? ?? '',
        path: json['path'] as String?,
        countOf: json['countOf'] as String?,
        pairWith: json['pairWith'] as String?,
        width: json['width'] as String?,
        align: json['align'] as String?,
      );

  final String label;

  /// Dot path to the value inside one record, e.g. `timelog.cycle`.
  final String? path;

  /// Render the length of a nested array instead of a value.
  final String? countOf;

  /// Render two values in one cell as `a / b`.
  final String? pairWith;

  final String? width;
  final String? align;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        if (path != null) 'path': path,
        if (countOf != null) 'countOf': countOf,
        if (pairWith != null) 'pairWith': pairWith,
        if (width != null) 'width': width,
        if (align != null) 'align': align,
      };
}

/// Printed in a summary cell when the underlying value is absent, as on paper.
const String emptyCell = '—';

/// Read a dot path out of one record.
///
/// A missing intermediate yields null rather than throwing, because a partly
/// filled record is the normal case — a nurse opens a treatment day and fills
/// it across a shift.
Object? readRecordPath(Object? record, String? path) {
  if (path == null || path.isEmpty) return null;

  Object? cursor = record;
  for (final key in path.split('.')) {
    if (cursor is Map) {
      cursor = cursor[key];
    } else if (cursor is List) {
      // JavaScript indexes arrays with string keys; Dart needs the parse made
      // explicit.
      final index = int.tryParse(key);
      if (index == null || index < 0 || index >= cursor.length) return null;
      cursor = cursor[index];
    } else {
      return null;
    }
  }
  return cursor;
}

/// Render a scalar the way `String(value)` would in JavaScript.
///
/// The whole-number case matters: JS prints `2` for `2.0`, Dart prints `2.0`.
/// Without this, a dose that round-trips through JSON as a double would read
/// differently here than in the web renderer.
String _scalarText(Object? value) {
  if (value == null || value == '') return emptyCell;
  if (value is bool) return value ? 'Yes' : 'No';
  if (value is num) return _numberText(value);
  return value.toString();
}

String _numberText(num value) {
  if (value is int) return value.toString();
  if (value.isFinite && value == value.truncateToDouble()) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Render one summary cell's text for a record.
String recordCellText(Object? record, RecordTableColumn column) {
  final countOf = column.countOf;
  if (countOf != null && countOf.isNotEmpty) {
    final value = readRecordPath(record, countOf);
    // An absent array reads as 0, not an em dash: a record seeded before the
    // array existed has genuinely logged nothing.
    return (value is List ? value.length : 0).toString();
  }

  final primary = readRecordPath(record, column.path);

  final pairWith = column.pairWith;
  if (pairWith != null && pairWith.isNotEmpty) {
    final secondary = readRecordPath(record, pairWith);
    return '${_scalarText(primary)} / ${_scalarText(secondary)}';
  }

  return _scalarText(primary);
}

/// Resolve the count line above the table.
///
/// `{n}` becomes the record count and `{s}` an empty string or `s`, so an
/// author can write `{n} treatment day{s} logged this month` and get the
/// singular and plural both right.
String recordCountText(String? template, int count) {
  if (template == null || template.isEmpty) {
    return '$count record${count == 1 ? '' : 's'}';
  }
  return template
      .replaceAll('{n}', '$count')
      .replaceAll('{s}', count == 1 ? '' : 's');
}

/// Seed a new record from the item schema.
///
/// Nested objects are present and arrays empty from the moment the record is
/// added, so its summary row reads correctly straight away instead of filling
/// in as the user types. Scalars are deliberately left absent — an untouched
/// field must stay missing so `required` validation still bites.
Map<String, dynamic> createRecordDefault(Map<String, dynamic>? schema) {
  final out = <String, dynamic>{};

  final properties = schema?['properties'];
  if (properties is! Map) return out;

  for (final entry in properties.entries) {
    final key = '${entry.key}';
    final property = entry.value;
    if (property is! Map<String, dynamic>) continue;

    if (property.containsKey('default')) {
      out[key] = property['default'];
    } else if (property['type'] == 'object') {
      out[key] = createRecordDefault(property);
    } else if (property['type'] == 'array') {
      out[key] = <dynamic>[];
    }
  }

  return out;
}

/// `insertedBy` → `Inserted by`, for a property with no title.
///
/// Note this lowercases everything after the first character, so it produces
/// `Inserted by` rather than `Inserted By`. That differs from the label
/// humanisation the renderer applies to control labels, and the difference is
/// upstream behaviour, not an oversight here — see [labelFromKey] in
/// `schema/labels.dart`.
String humanizeRecordKey(String key) {
  final spaced = key
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]} ${match[2]}',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ');

  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1).toLowerCase();
}

/// Derive summary columns for an array the author never configured.
///
/// Picks the leading scalar properties, which in practice are the identifying
/// ones — a date, a name, a code — because generators emit them first. Nested
/// objects and arrays are skipped; they belong in the detail panel, not a cell.
List<RecordTableColumn> deriveRecordColumns(
  Map<String, dynamic>? itemSchema, [
  int limit = 4,
]) {
  final columns = <RecordTableColumn>[];

  final properties = itemSchema?['properties'];
  if (properties is! Map) return columns;

  for (final entry in properties.entries) {
    if (columns.length >= limit) break;

    final key = '${entry.key}';
    final property = entry.value;
    if (property is! Map<String, dynamic>) continue;

    final rawType = property['type'];
    final type =
        rawType is List ? (rawType.isEmpty ? null : rawType.first) : rawType;
    if (type == 'object' || type == 'array') continue;

    final title = property['title'];
    columns.add(
      RecordTableColumn(
        label: title is String ? title : humanizeRecordKey(key),
        path: key,
      ),
    );
  }

  return columns;
}

/// Whether a summary column can be edited straight in the table cell.
///
/// A column naming one concrete field is editable — the cell renders that
/// field's real control, so a row behaves like the grid it was converted from.
/// Derived columns cannot: `countOf` counts a nested array and `pairWith`
/// merges two fields, so neither maps back to a single value to write.
bool isColumnEditable(RecordTableColumn column) {
  final path = column.path;
  return path != null &&
      path.isNotEmpty &&
      (column.countOf == null || column.countOf!.isEmpty) &&
      (column.pairWith == null || column.pairWith!.isEmpty);
}

/// Field names of a record that are not already shown as summary columns.
///
/// Decides whether a row needs a detail panel at all: when every field is
/// inline, an "Open" button would reveal an empty panel, so it is hidden.
List<String> fieldsOutsideColumns(
  Map<String, dynamic>? itemSchema,
  List<RecordTableColumn> columns,
) {
  final shown = <String>{
    for (final column in columns)
      ...<String?>[
        column.path,
        column.pairWith,
        column.countOf,
      ].whereType<String>().where((value) => value.isNotEmpty),
  };

  final properties = itemSchema?['properties'];
  if (properties is! Map) return const <String>[];

  return properties.keys
      .map((key) => '$key')
      .where((key) => !shown.contains(key))
      .toList();
}
