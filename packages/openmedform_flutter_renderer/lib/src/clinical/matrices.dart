/// The two checkbox grids: `scoringMatrix` and `checklistMatrix`.
///
/// Ported from `clinical-controls.tsx` in the React renderer.
library;

import 'package:flutter/material.dart';

import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';
import '../widgets/field_frame.dart';
import '../widgets/omf_table.dart';

List<Map<String, dynamic>> _mapList(Object? raw) => raw is List
    ? raw.whereType<Map<String, dynamic>>().toList()
    : const <Map<String, dynamic>>[];

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

/// A "Risk factor / Points / Present" table.
///
/// The value is a flat `{field: bool}` map. The subtotal is computed locally
/// from the checked rows — not through form-core, matching the web renderer —
/// and is a clinician aid only: the server recalculates the authoritative
/// score on submission.
class OmfScoringMatrix extends StatelessWidget {
  const OmfScoringMatrix({required this.context, super.key});

  final RenderContext context;

  Map<String, dynamic> get _value {
    final value = context.value;
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  void _toggle(String field, bool checked) {
    final updated = Map<String, dynamic>.from(_value)..[field] = checked;
    context.store.updateAt(context.path, updated);
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final domains = _mapList(context.omf?['domains']);

    num total = 0;
    final rows = <List<OmfCell>>[
      <OmfCell>[
        OmfCell.text('Risk Factor',
            bold: true, background: theme.sectionBackground),
        OmfCell.text('Points', bold: true, background: theme.sectionBackground),
        OmfCell.text('Present',
            bold: true, background: theme.sectionBackground),
      ],
    ];

    for (final domain in domains) {
      final name = _string(domain['name']);
      if (name.isNotEmpty) {
        rows.add(<OmfCell>[
          OmfCell.text(
            name,
            bold: true,
            columnSpan: 3,
            background: theme.sectionBackground,
          ),
        ]);
      }

      for (final item in _mapList(domain['items'])) {
        final field = _string(item['field']);
        if (field.isEmpty) continue;

        final points = item['points'] is num ? item['points'] as num : 0;
        final checked = _value[field] == true;
        if (checked) total += points;

        rows.add(<OmfCell>[
          OmfCell.text(_string(item['label'], field)),
          OmfCell.text('$points'),
          OmfCell(
            _MatrixCheckbox(
              checked: checked,
              enabled: context.enabled,
              semanticLabel: _string(item['label'], field),
              onChanged: (next) => _toggle(field, next),
            ),
            align: TextAlign.center,
          ),
        ]);
      }
    }

    rows.add(<OmfCell>[
      OmfCell.text(
        'Subtotal (server recalculates)',
        bold: true,
        columnSpan: 2,
      ),
      OmfCell.text('$total', bold: true),
    ]);

    return FieldFrame.forContext(
      context,
      child: OmfTable(rows: rows, columnWidths: const <int>[6, 2, 2]),
    );
  }
}

/// A rows × columns checkbox grid, e.g. an item against each day of a stay.
///
/// The value is `{rowKey: {colKey: true}}`. **Unchecking deletes the key**
/// rather than writing `false`, and a row map left empty is removed — writing
/// `false` would produce different submission JSON for the same clinical input
/// than the web renderers do.
class OmfChecklistMatrix extends StatelessWidget {
  const OmfChecklistMatrix({required this.context, super.key});

  final RenderContext context;

  Map<String, dynamic> get _value {
    final value = context.value;
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  void _toggle(String rowKey, String colKey, bool checked) {
    final current = _value[rowKey];
    final row = current is Map<String, dynamic>
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};

    if (checked) {
      row[colKey] = true;
    } else {
      row.remove(colKey);
    }

    final updated = Map<String, dynamic>.from(_value);
    if (row.isEmpty) {
      updated.remove(rowKey);
    } else {
      updated[rowKey] = row;
    }

    context.store.updateAt(context.path, updated);
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final rows = _mapList(context.omf?['rows']);
    final columns = _mapList(context.omf?['columns']);

    return FieldFrame.forContext(
      context,
      child: OmfTable(
        scrollHorizontally: true,
        minWidth: (columns.length + 1) * theme.tableColumnMinWidth,
        columnWidths: <int>[3, for (var i = 0; i < columns.length; i++) 1],
        rows: <List<OmfCell>>[
          <OmfCell>[
            OmfCell.text('', background: theme.sectionBackground),
            for (final column in columns)
              OmfCell.text(
                _string(column['label'], _string(column['key'])),
                align: TextAlign.center,
                bold: true,
                background: theme.sectionBackground,
              ),
          ],
          for (final row in rows)
            <OmfCell>[
              OmfCell.text(_string(row['label'], _string(row['key']))),
              for (final column in columns)
                OmfCell(
                  _MatrixCheckbox(
                    checked: _checked(
                      _string(row['key']),
                      _string(column['key']),
                    ),
                    enabled: context.enabled,
                    semanticLabel:
                        '${_string(row['label'], _string(row['key']))} — '
                        '${_string(column['label'], _string(column['key']))}',
                    onChanged: (next) => _toggle(
                      _string(row['key']),
                      _string(column['key']),
                      next,
                    ),
                  ),
                  align: TextAlign.center,
                ),
            ],
        ],
      ),
    );
  }

  bool _checked(String rowKey, String colKey) {
    final row = _value[rowKey];
    return row is Map && row[colKey] == true;
  }
}

class _MatrixCheckbox extends StatelessWidget {
  const _MatrixCheckbox({
    required this.checked,
    required this.enabled,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: checked,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
          ),
        ),
      );
}
