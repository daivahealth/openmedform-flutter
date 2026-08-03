/// Clinical controls: radio, signature block, risk display, and the read-only
/// reference tables.
///
/// Ported from `clinical-controls.tsx` and `omf-controls.tsx` in the React
/// renderer. Configuration rides on `options.omf`; the bound value rides on the
/// data at the control's scope.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';
import '../widgets/field_frame.dart';
import '../widgets/omf_table.dart';

List<Map<String, dynamic>> _mapList(Object? raw) => raw is List
    ? raw.whereType<Map<String, dynamic>>().toList()
    : const <Map<String, dynamic>>[];

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

/// Enum options as radio buttons.
///
/// Exactly two options defaults to label-left / options-right — the paper
/// YES/NO row that dominates clinical forms. `screen.labelPosition` and
/// `screen.inline` override.
class OmfRadioControl extends StatelessWidget {
  const OmfRadioControl({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final options = context.fieldSchema?.enumValues ?? const <Object?>[];

    final screen = context.omf?['screen'];
    final labelPosition = screen is Map ? screen['labelPosition'] : null;
    final labelLeft =
        labelPosition is String ? labelPosition == 'left' : options.length == 2;
    final inlineValue = screen is Map ? screen['inline'] : null;
    final inline = inlineValue is bool ? inlineValue : labelLeft;

    // RadioGroup requires a non-null handler; disabling is expressed on each
    // Radio, which then never reports a change.
    Widget group(Widget child) => RadioGroup<Object?>(
          groupValue: context.value,
          onChanged: (selected) {
            if (context.enabled) {
              context.store.updateAt(context.path, selected);
            }
          },
          child: child,
        );

    final buttons = <Widget>[
      for (final option in options)
        _RadioOption(
          option: option,
          enabled: context.enabled,
          // The web wraps each option in a <label>, so its text is part of the
          // tap target. Reproduce that rather than making clinicians hit the
          // 24px circle.
          onSelect: () => context.store.updateAt(context.path, option),
        ),
    ];

    if (labelLeft) {
      final label =
          controlLabel(context.element, fieldSchema: context.fieldSchema);

      return Padding(
        padding: EdgeInsets.only(bottom: theme.fieldGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: label,
                      children: <InlineSpan>[
                        if (context.isRequired)
                          TextSpan(
                            text: ' *',
                            style: TextStyle(color: theme.invalid),
                          ),
                      ],
                    ),
                    style: theme.labelStyle,
                  ),
                ),
                // Flexible, so a long label plus its options cannot overflow
                // the row on a narrow screen.
                Flexible(
                  child: group(
                    Wrap(
                        spacing: 16,
                        alignment: WrapAlignment.end,
                        children: buttons),
                  ),
                ),
              ],
            ),
            if (context.errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  context.errors.first.message,
                  style: theme.errorStyle,
                ),
              ),
          ],
        ),
      );
    }

    return FieldFrame.forContext(
      context,
      child: group(
        inline
            ? Wrap(spacing: 16, runSpacing: 4, children: buttons)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final button in buttons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: button,
                    ),
                ],
              ),
      ),
    );
  }
}

/// One radio option. Selection state is owned by the enclosing [RadioGroup];
/// [onSelect] extends the tap target to the option's text.
class _RadioOption extends StatelessWidget {
  const _RadioOption({
    required this.option,
    required this.enabled,
    required this.onSelect,
  });

  final Object? option;
  final bool enabled;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return InkWell(
      onTap: enabled ? onSelect : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 24,
            height: 24,
            child: Radio<Object?>(value: option, enabled: enabled),
          ),
          const SizedBox(width: 4),
          // A long option inside a narrow table cell must ellipsise rather
          // than overflow its row.
          Flexible(
            child: Text(
              '$option',
              style: theme.bodyStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A printed name plus a date.
///
/// Typed, not drawn: every shipped renderer captures a signature this way, and
/// adding drawing here would be renderer divergence rather than a feature.
class OmfSignatureDateControl extends StatelessWidget {
  const OmfSignatureDateControl({required this.context, super.key});

  final RenderContext context;

  Map<String, dynamic> get _value {
    final value = context.value;
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  void _update(String key, String? next) {
    final updated = Map<String, dynamic>.from(_value);
    if (next == null || next.isEmpty) {
      updated.remove(key);
    } else {
      updated[key] = next;
    }
    context.store.updateAt(context.path, updated);
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final date = _string(_value['date']);

    return FieldFrame.forContext(
      context,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: TextFormField(
              initialValue: _string(_value['printedName']),
              enabled: context.enabled,
              style: theme.bodyStyle,
              decoration: omfInputDecoration(theme, hintText: 'Printed name'),
              onChanged: (next) => _update('printedName', next),
            ),
          ),
          SizedBox(width: theme.controlGap),
          SizedBox(
            width: 180,
            child: InkWell(
              onTap: context.enabled
                  ? () async {
                      final picked = await showDatePicker(
                        context: buildContext,
                        initialDate: DateTime.tryParse(date) ?? DateTime.now(),
                        firstDate: DateTime(1900),
                        lastDate: DateTime(2200),
                      );
                      if (picked != null) {
                        _update(
                          'date',
                          '${picked.year.toString().padLeft(4, '0')}-'
                              '${picked.month.toString().padLeft(2, '0')}-'
                              '${picked.day.toString().padLeft(2, '0')}',
                        );
                      }
                    }
                  : null,
              child: InputDecorator(
                decoration: omfInputDecoration(theme).copyWith(
                  suffixIcon: Icon(Icons.calendar_today, size: theme.bodySize),
                ),
                child: Text(
                  date,
                  style: theme.bodyStyle.copyWith(
                    color: date.isEmpty ? theme.muted : theme.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Echoes the stored risk, or says the server will compute it.
class OmfRiskStratificationControl extends StatelessWidget {
  const OmfRiskStratificationControl({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final value = context.value;
    final text =
        value == null || value == '' ? 'Calculated on submission' : '$value';

    return FieldFrame.forContext(
      context,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(theme.controlPadding),
        decoration: BoxDecoration(
          border: Border.all(color: theme.border, width: theme.borderWidth),
          borderRadius: BorderRadius.circular(theme.borderRadius),
          color: theme.sectionBackground,
        ),
        child: Text(text, style: theme.bodyStyle),
      ),
    );
  }
}

/// A read-only table of recorded observation rows.
class OmfVitalSignsChart extends StatelessWidget {
  const OmfVitalSignsChart({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final columns = _mapList(context.omf?['columns']);
    final value = context.value;
    final rows = value is List
        ? value.whereType<Map<String, dynamic>>().toList()
        : const <Map<String, dynamic>>[];

    if (columns.isEmpty) {
      return FieldFrame.forContext(
        context,
        child: Text('No columns configured.', style: theme.helpStyle),
      );
    }

    return FieldFrame.forContext(
      context,
      child: OmfTable(
        scrollHorizontally: true,
        minWidth: columns.length * theme.tableColumnMinWidth,
        rows: <List<OmfCell>>[
          <OmfCell>[
            for (final column in columns)
              OmfCell.text(
                _string(column['label'], _string(column['key'])),
                bold: true,
                background: theme.sectionBackground,
              ),
          ],
          for (final row in rows)
            <OmfCell>[
              for (final column in columns)
                OmfCell.text(_cellText(row[_string(column['key'])])),
            ],
        ],
      ),
    );
  }

  static String _cellText(Object? value) => value == null ? '' : '$value';
}

/// Colour-banded reference rows, e.g. an early-warning score key.
class OmfColorCodedGrid extends StatelessWidget {
  const OmfColorCodedGrid({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final rows = _mapList(context.omf?['rows']);

    return FieldFrame.forContext(
      context,
      child: OmfTable(
        rows: <List<OmfCell>>[
          for (final row in rows)
            <OmfCell>[
              OmfCell.text(
                _string(row['label']),
                background: parseCssColor(_string(row['color'])),
              ),
              OmfCell.text(
                _string(row['range']),
                background: parseCssColor(_string(row['color'])),
              ),
            ],
        ],
      ),
    );
  }
}

/// A static reference table of headers and string rows.
class OmfClinicalReferenceTable extends StatelessWidget {
  const OmfClinicalReferenceTable({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);

    final rawHeaders = context.omf?['headers'];
    final headers = rawHeaders is List
        ? rawHeaders.map((header) => '$header').toList()
        : const <String>[];

    final rawRows = context.omf?['rows'];
    final rows = rawRows is List
        ? rawRows
            .whereType<List<Object?>>()
            .map((row) => row.map((cell) => '$cell').toList())
            .toList()
        : const <List<String>>[];

    return FieldFrame.forContext(
      context,
      child: OmfTable(
        scrollHorizontally: headers.length > 3,
        minWidth: headers.length * theme.tableColumnMinWidth,
        rows: <List<OmfCell>>[
          if (headers.isNotEmpty)
            <OmfCell>[
              for (final header in headers)
                OmfCell.text(
                  header,
                  bold: true,
                  background: theme.sectionBackground,
                ),
            ],
          for (final row in rows)
            <OmfCell>[for (final cell in row) OmfCell.text(cell)],
        ],
      ),
    );
  }
}

/// Parse a `#rrggbb`, `#rgb` or `#rrggbbaa` colour from a schema string.
Color? parseCssColor(String value) {
  var hex = value.trim().replaceFirst('#', '');
  if (hex.isEmpty) return null;
  if (hex.length == 3) {
    hex = hex.split('').map((char) => '$char$char').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;

  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}
