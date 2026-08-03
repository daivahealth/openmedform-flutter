/// `recordTable` — a repeating encounter log.
///
/// Ported from `record-table.tsx` in the React renderer.
///
/// Clinical forms very often carry a table the user adds rows to, where the
/// table is only a summary and the real form lives behind each row: a treatment
/// day, a medication round, an observation entry. Stock JSON Forms renders an
/// array of objects as a generic list widget, which looks nothing like the
/// paper it replaces and buries the fields. This renders a toolbar, a summary
/// table, and one inline detail panel at a time.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/dispatcher.dart';
import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';

String _string(Object? value, [String fallback = '']) =>
    value is String && value.isNotEmpty ? value : fallback;

/// Keeps several horizontal scroll views at the same offset.
///
/// Each summary row scrolls independently so the actions column can sit
/// *outside* the scrolling area and stay reachable at any width — on a wide
/// converted chart, an unreachable remove button means a row that cannot be
/// deleted at all. Written here rather than taken from
/// `linked_scroll_controller`, which has not been published since 2021 and
/// still declares a pre-Dart-3 SDK constraint.
class _ScrollSyncGroup {
  final List<ScrollController> _controllers = <ScrollController>[];
  bool _syncing = false;

  ScrollController create() {
    final controller = ScrollController();
    controller.addListener(() {
      if (_syncing || !controller.hasClients) return;
      _syncing = true;
      for (final other in _controllers) {
        if (identical(other, controller)) continue;
        if (other.hasClients && other.offset != controller.offset) {
          other.jumpTo(controller.offset.clamp(
            other.position.minScrollExtent,
            other.position.maxScrollExtent,
          ));
        }
      }
      _syncing = false;
    });
    _controllers.add(controller);
    return controller;
  }

  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
  }
}

class OmfRecordTable extends StatefulWidget {
  const OmfRecordTable({required this.context, super.key});

  final RenderContext context;

  @override
  State<OmfRecordTable> createState() => _OmfRecordTableState();
}

class _OmfRecordTableState extends State<OmfRecordTable> {
  int? _openIndex;
  _ScrollSyncGroup _scrollGroup = _ScrollSyncGroup();
  int _stripCount = -1;

  @override
  void dispose() {
    _scrollGroup.dispose();
    super.dispose();
  }

  RenderContext get _context => widget.context;

  Map<String, dynamic> get _config {
    final config = _context.omf?['recordTable'];
    return config is Map<String, dynamic> ? config : const <String, dynamic>{};
  }

  /// The array's item schema — what a row's fields are described by.
  JsonSchema? get _itemSchema {
    final items = _context.fieldSchema?['items'];
    return items is Map<String, dynamic> ? items : null;
  }

  List<Object?> get _records {
    final value = _context.value;
    return value is List ? value : const <Object?>[];
  }

  List<RecordTableColumn> get _columns {
    final configured = _config['columns'];
    if (configured is List && configured.isNotEmpty) {
      return configured
          .whereType<Map<String, dynamic>>()
          .map(RecordTableColumn.fromJson)
          .toList();
    }
    // An array the author never configured still gets a usable table rather
    // than a generic list widget.
    return deriveRecordColumns(_itemSchema);
  }

  /// The per-record layout: `options.detail` when supplied, else generated.
  Map<String, dynamic> get _detailUiSchema {
    final options = _context.element['options'];
    final detail = options is Map ? options['detail'] : null;
    if (detail is Map<String, dynamic>) return detail;
    return generateUiSchema(_itemSchema);
  }

  /// False when every field is already a column, so a panel would be empty.
  bool get _hasDetail => fieldsOutsideColumns(_itemSchema, _columns).isNotEmpty;

  void _writeRecords(List<Object?> records) =>
      _context.store.updateAt(_context.path, records);

  void _add() {
    final records = List<Object?>.from(_records)
      ..add(createRecordDefault(_itemSchema));
    _writeRecords(records);
    // The new record is appended, so it is the one to open.
    setState(() => _openIndex = records.length - 1);
  }

  Future<void> _remove(int index) async {
    final confirm = _config['removeConfirm'];
    if (confirm is String && confirm.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(confirm),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final records = List<Object?>.from(_records);
    if (index < 0 || index >= records.length) return;
    records.removeAt(index);
    _writeRecords(records);

    setState(() {
      final open = _openIndex;
      if (open == null) return;
      if (open == index) {
        _openIndex = null;
      } else if (open > index) {
        _openIndex = open - 1;
      }
    });
  }

  /// A live control for one editable cell.
  ///
  /// Dispatching a real Control at `<path>.<index>.<field>` reuses every
  /// existing renderer, so an inline cell behaves exactly like the same field
  /// in the detail panel and writes to the same place. Its label is suppressed
  /// because the column header already names it.
  Widget _cellControl(int index, RecordTableColumn column) {
    final segments = (column.path ?? '').split('.');
    final scope = '#/properties/${segments.join('/properties/')}';

    return DispatchRenderer(
      element: <String, dynamic>{
        'type': 'Control',
        'scope': scope,
        'label': false,
      },
      path: <String>[..._context.path, '$index'],
      schemaRoot: _itemSchema,
      suppressLabel: true,
      enabled: _context.enabled,
      // Summary rows are fixed height, so a cell must not measure itself.
      inMeasuredRow: true,
    );
  }

  Widget _detailPanel(int index) {
    final theme = OmfTheme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(theme.controlPadding),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border.all(color: theme.border, width: theme.borderWidth),
      ),
      child: DispatchRenderer(
        element: _detailUiSchema,
        path: <String>[..._context.path, '$index'],
        schemaRoot: _itemSchema,
        enabled: _context.enabled,
      ),
    );
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final columns = _columns;
    final records = _records;
    final count = records.length;

    // One strip per summary row, plus the header.
    if (_stripCount != count + 1) {
      _scrollGroup.dispose();
      _scrollGroup = _ScrollSyncGroup();
      _stripCount = count + 1;
    }

    final byColumn = _config['orientation'] == 'columns';
    final label = controlLabel(
      _context.element,
      fieldSchema: _context.fieldSchema,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: theme.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Toolbar(
            countText: recordCountText(
              _config['countLabel'] as String?,
              count,
            ),
            addLabel: _string(
              _config['addLabel'],
              '+ Add ${label.isEmpty ? 'record' : label}',
            ),
            enabled: _context.enabled,
            onAdd: _add,
          ),
          if (count == 0)
            _EmptyState(
                label: _string(_config['emptyLabel'], 'No records yet.'))
          else if (byColumn)
            _ColumnOriented(
              columns: columns,
              records: records,
              instanceLabel: _string(_config['instanceLabel'], 'Record'),
              openIndex: _openIndex,
              enabled: _context.enabled,
              hasDetail: _hasDetail,
              scrollGroup: _scrollGroup,
              onToggle: (index) => setState(
                () => _openIndex = _openIndex == index ? null : index,
              ),
              onRemove: _remove,
              detailBuilder: _detailPanel,
            )
          else
            _RowOriented(
              columns: columns,
              records: records,
              openIndex: _openIndex,
              enabled: _context.enabled,
              hasDetail: _hasDetail,
              scrollGroup: _scrollGroup,
              onToggle: (index) => setState(
                () => _openIndex = _openIndex == index ? null : index,
              ),
              onRemove: _remove,
              cellControl: _cellControl,
              detailBuilder: _detailPanel,
            ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.countText,
    required this.addLabel,
    required this.enabled,
    required this.onAdd,
  });

  final String countText;
  final String addLabel;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              countText,
              style: theme.labelStyle.copyWith(
                fontFamily: theme.monoFontFamily,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
          FilledButton(
            onPressed: enabled ? onAdd : null,
            style: FilledButton.styleFrom(
              backgroundColor: theme.accent,
              foregroundColor: theme.headerForeground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(theme.borderRadius),
              ),
            ),
            child: Text(addLabel),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(theme.controlPadding * 2),
      decoration: BoxDecoration(
        border: Border.all(color: theme.border, width: theme.borderWidth),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.bodyStyle.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.muted,
        ),
      ),
    );
  }
}

/// The actions cell: Open/Close and remove, pinned outside the scroll area.
class _ActionsCell extends StatelessWidget {
  const _ActionsCell({
    required this.index,
    required this.isOpen,
    required this.enabled,
    required this.hasDetail,
    required this.onToggle,
    required this.onRemove,
    required this.height,
  });

  final int index;
  final bool isOpen;
  final bool enabled;
  final bool hasDetail;
  final VoidCallback onToggle;
  final VoidCallback onRemove;
  final double height;

  /// Wide enough for "Close" plus the remove button at the body text size.
  static const double width = 156;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: theme.controlPadding / 2),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          left: BorderSide(color: theme.border, width: theme.borderWidth),
          bottom: BorderSide(color: theme.border, width: theme.borderWidth),
          right: BorderSide(color: theme.border, width: theme.borderWidth),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasDetail)
            Flexible(
              child: TextButton(
                onPressed: onToggle,
                style: TextButton.styleFrom(
                  foregroundColor: theme.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  isOpen ? 'Close' : 'Open',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          if (enabled)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove record ${index + 1}',
              icon: const Icon(Icons.close, size: 16),
              color: theme.danger,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// A header or body strip that scrolls horizontally in step with its siblings.
class _Strip extends StatefulWidget {
  const _Strip({
    required this.group,
    required this.width,
    required this.height,
    required this.child,
  });

  final _ScrollSyncGroup group;
  final double width;
  final double height;
  final Widget child;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  late final ScrollController _controller = widget.group.create();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: widget.width, child: widget.child),
        ),
      );
}

double _columnWidth(RecordTableColumn column, double fallback) {
  final width = column.width;
  if (width == null) return fallback;
  final parsed = double.tryParse(width.replaceAll(RegExp('[^0-9.]'), ''));
  return parsed == null || parsed <= 0 ? fallback : math.max(parsed, 80);
}

class _RowOriented extends StatelessWidget {
  const _RowOriented({
    required this.columns,
    required this.records,
    required this.openIndex,
    required this.enabled,
    required this.hasDetail,
    required this.scrollGroup,
    required this.onToggle,
    required this.onRemove,
    required this.cellControl,
    required this.detailBuilder,
  });

  final List<RecordTableColumn> columns;
  final List<Object?> records;
  final int? openIndex;
  final bool enabled;
  final bool hasDetail;
  final _ScrollSyncGroup scrollGroup;
  final void Function(int index) onToggle;
  final void Function(int index) onRemove;
  final Widget Function(int index, RecordTableColumn column) cellControl;
  final Widget Function(int index) detailBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);
    final rowHeight = theme.rowMinHeight + theme.controlPadding * 2;

    return LayoutBuilder(
      builder: (_, constraints) {
        final available =
            math.max(constraints.maxWidth - _ActionsCell.width, 120.0);
        final widths = <double>[
          for (final column in columns)
            _columnWidth(column, available / math.max(columns.length, 1)),
        ];
        final tableWidth = math.max(
          widths.fold<double>(0, (sum, width) => sum + width),
          available,
        );
        final scale = tableWidth == 0 ? 1.0 : available / tableWidth;
        final resolved = <double>[
          for (final width in widths) scale > 1 ? width * scale : width,
        ];
        final totalWidth =
            resolved.fold<double>(0, (sum, width) => sum + width);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _Strip(
                    group: scrollGroup,
                    width: totalWidth,
                    height: rowHeight,
                    child: Row(
                      children: <Widget>[
                        for (var i = 0; i < columns.length; i++)
                          _HeaderCell(
                            label: columns[i].label,
                            width: resolved[i],
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: _ActionsCell.width,
                  height: rowHeight,
                  decoration: BoxDecoration(
                    color: theme.headerBackground,
                    border: Border.all(
                      color: theme.border,
                      width: theme.borderWidth,
                    ),
                  ),
                ),
              ],
            ),
            for (var index = 0; index < records.length; index++) ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Strip(
                      group: scrollGroup,
                      width: totalWidth,
                      height: rowHeight,
                      child: Row(
                        children: <Widget>[
                          for (var i = 0; i < columns.length; i++)
                            _BodyCell(
                              width: resolved[i],
                              highlighted: openIndex == index,
                              // A column naming one field is edited in place,
                              // exactly as the source grid does. Derived
                              // columns — a nested-array count, a paired
                              // "A / B" — have no single value to write back,
                              // so they stay read-only text.
                              child: isColumnEditable(columns[i])
                                  ? cellControl(index, columns[i])
                                  : Text(
                                      recordCellText(
                                        records[index],
                                        columns[i],
                                      ),
                                      style: theme.bodyStyle,
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  _ActionsCell(
                    index: index,
                    isOpen: openIndex == index,
                    enabled: enabled,
                    hasDetail: hasDetail,
                    height: rowHeight,
                    onToggle: () => onToggle(index),
                    onRemove: () => onRemove(index),
                  ),
                ],
              ),
              if (openIndex == index) detailBuilder(index),
            ],
          ],
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({required this.label, required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return Container(
      width: width,
      padding: EdgeInsets.all(theme.controlPadding),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.headerBackground,
        border: Border(
          right: BorderSide(color: theme.border, width: theme.borderWidth),
        ),
      ),
      child: Text(
        label.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.labelStyle.copyWith(
          color: theme.headerForeground,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell({
    required this.width,
    required this.child,
    required this.highlighted,
  });

  final double width;
  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: theme.controlPadding),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: highlighted ? theme.sectionBackground : null,
        border: Border(
          right: BorderSide(color: theme.border, width: theme.borderWidth),
          bottom: BorderSide(color: theme.border, width: theme.borderWidth),
          left: BorderSide(color: theme.border, width: theme.borderWidth),
        ),
      ),
      child: child,
    );
  }
}

/// Records as columns: field labels down the left, one column per record.
///
/// This is how paper charts that compare instances side by side are drawn — a
/// cannula chart puts "Date of insertion", "Site", "Gauge" down the side and
/// gives each cannula its own column. The data is identical to row orientation;
/// only the axes swap.
class _ColumnOriented extends StatelessWidget {
  const _ColumnOriented({
    required this.columns,
    required this.records,
    required this.instanceLabel,
    required this.openIndex,
    required this.enabled,
    required this.hasDetail,
    required this.scrollGroup,
    required this.onToggle,
    required this.onRemove,
    required this.detailBuilder,
  });

  final List<RecordTableColumn> columns;
  final List<Object?> records;
  final String instanceLabel;
  final int? openIndex;
  final bool enabled;
  final bool hasDetail;
  final _ScrollSyncGroup scrollGroup;
  final void Function(int index) onToggle;
  final void Function(int index) onRemove;
  final Widget Function(int index) detailBuilder;

  static const double _labelWidth = 170;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);
    final rowHeight = theme.rowMinHeight + theme.controlPadding * 2;
    final recordWidth = math.max(theme.tableColumnMinWidth, 140.0);
    final stripWidth = recordWidth * records.length;

    Widget strip(Widget child) => _Strip(
          group: scrollGroup,
          width: stripWidth,
          height: rowHeight,
          child: child,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            _CornerCell(
              width: _labelWidth,
              height: rowHeight,
              label: 'Parameter',
            ),
            Expanded(
              child: strip(
                Row(
                  children: <Widget>[
                    for (var index = 0; index < records.length; index++)
                      _HeaderCell(
                        label: '$instanceLabel ${index + 1}',
                        width: recordWidth,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        for (final column in columns)
          Row(
            children: <Widget>[
              _CornerCell(
                width: _labelWidth,
                height: rowHeight,
                label: column.label,
                header: false,
              ),
              Expanded(
                child: strip(
                  Row(
                    children: <Widget>[
                      for (var index = 0; index < records.length; index++)
                        _BodyCell(
                          width: recordWidth,
                          highlighted: openIndex == index,
                          child: Text(
                            recordCellText(records[index], column),
                            style: theme.bodyStyle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        Row(
          children: <Widget>[
            SizedBox(width: _labelWidth, height: rowHeight),
            Expanded(
              child: strip(
                Row(
                  children: <Widget>[
                    for (var index = 0; index < records.length; index++)
                      SizedBox(
                        width: recordWidth,
                        child: _ActionsCell(
                          index: index,
                          isOpen: openIndex == index,
                          enabled: enabled,
                          hasDetail: hasDetail,
                          height: rowHeight,
                          onToggle: () => onToggle(index),
                          onRemove: () => onRemove(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (openIndex != null && openIndex! < records.length)
          detailBuilder(openIndex!),
      ],
    );
  }
}

class _CornerCell extends StatelessWidget {
  const _CornerCell({
    required this.width,
    required this.height,
    required this.label,
    this.header = true,
  });

  final double width;
  final double height;
  final String label;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(theme.controlPadding),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: header ? theme.headerBackground : theme.sectionBackground,
        border: Border.all(color: theme.border, width: theme.borderWidth),
      ),
      child: Text(
        header ? label.toUpperCase() : label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.labelStyle.copyWith(
          color: header ? theme.headerForeground : theme.label,
        ),
      ),
    );
  }
}

/// Matches an explicit `recordTable`, and also any array-of-objects control
/// that carries no omf config at all.
///
/// The second half is the safety net: without it, such an array falls through
/// to a generic list widget, which is unusable on a clinical form. A derived
/// table is imperfect; that widget is broken.
int recordTableTester(Map<String, dynamic> element, ControlContext? context) {
  if (omfControl(element) == 'recordTable') return 20;
  if (element['type'] != 'Control') return notApplicable;

  final schema = context?.fieldSchema;
  if (schema == null || !schema.hasType('array')) return notApplicable;

  final items = schema['items'];
  final isObjectArray =
      items is Map<String, dynamic> && items['type'] == 'object';
  return isObjectArray ? 20 : notApplicable;
}
