/// The two custom `Omf*` layouts that are actually implemented: a paper-style
/// table and a tab strip.
///
/// The other ten `Omf*` types in the vocabulary exist in no renderer and are
/// emitted by no generator, so they are deliberately absent — see
/// docs/ARCHITECTURE.md section 9. They render as loud placeholders instead.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/dispatcher.dart';
import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';

List<Map<String, dynamic>> _mapList(Object? raw) => raw is List
    ? raw.whereType<Map<String, dynamic>>().toList()
    : const <Map<String, dynamic>>[];

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

/// A grid of `OmfTableRow`s, reproducing a paper form's ruled table.
///
/// Two modes, as upstream:
///
/// - With `omf.columns`, a real header row is drawn and each row's children
///   become one cell each, with their own labels suppressed — the column
///   heading already names the field.
/// - Without, each row is a two-cell `row label | contents` pair.
class OmfTableLayout extends StatelessWidget {
  const OmfTableLayout({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final columns = _mapList(context.omf?['columns']);
    final rows = childElements(context.element);
    final side = BorderSide(color: theme.border, width: theme.borderWidth);

    return Padding(
      padding: EdgeInsets.only(bottom: theme.sectionGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border.all(
          color: theme.border,
          width: theme.borderWidth,
        )),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (columns.isNotEmpty)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < columns.length; i++)
                      Expanded(
                        flex: _columnFlex(columns[i]),
                        child: Container(
                          padding: EdgeInsets.all(theme.controlPadding),
                          decoration: BoxDecoration(
                            color: theme.sectionBackground,
                            border: Border(
                              left: i == 0 ? BorderSide.none : side,
                              bottom: side,
                            ),
                          ),
                          child: Text(
                            _string(
                              columns[i]['label'],
                              _string(columns[i]['key']),
                            ),
                            style: theme.labelStyle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            for (final row in rows)
              _TableRow(
                context: context,
                row: row,
                columns: columns,
                side: side,
              ),
          ],
        ),
      ),
    );
  }

  static int _columnFlex(Map<String, dynamic> column) {
    final width = column['width'];
    if (width is num) return width.toInt().clamp(1, 100);
    return 1;
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.context,
    required this.row,
    required this.columns,
    required this.side,
  });

  final RenderContext context;
  final Map<String, dynamic> row;
  final List<Map<String, dynamic>> columns;
  final BorderSide side;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final cells = childElements(row);

    Widget cell(Widget child,
            {required bool first, int flex = 1, Color? background}) =>
        Expanded(
          flex: flex,
          child: Container(
            padding: EdgeInsets.all(theme.controlPadding),
            decoration: BoxDecoration(
              color: background,
              border: Border(
                left: first ? BorderSide.none : side,
                bottom: side,
              ),
            ),
            child: child,
          ),
        );

    // Column mode: one cell per child, labels suppressed because the header row
    // already names each column.
    if (columns.isNotEmpty) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < cells.length; i++)
              cell(
                DispatchRenderer(
                  element: cells[i],
                  path: context.path,
                  suppressLabel: true,
                  enabled: context.enabled,
                  schemaRoot: context.schemaRoot,
                  inMeasuredRow: true,
                ),
                first: i == 0,
                flex: i < columns.length
                    ? OmfTableLayout._columnFlex(columns[i])
                    : 1,
              ),
          ],
        ),
      );
    }

    // Label mode: `row label | contents`.
    final label = _string(row['label']);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          cell(
            Text(label, style: theme.labelStyle),
            first: true,
            flex: 2,
            background: theme.sectionBackground,
          ),
          cell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final child in cells)
                  DispatchRenderer(
                    element: child,
                    path: context.path,
                    suppressLabel: true,
                    enabled: context.enabled,
                    schemaRoot: context.schemaRoot,
                    inMeasuredRow: true,
                  ),
              ],
            ),
            first: false,
            flex: 5,
          ),
        ],
      ),
    );
  }
}

/// A tab strip over child pages.
///
/// **Only the active page is built.** Not [TabBarView], which keeps every page
/// alive: mounting hidden pages would run their rules and validation for
/// content the clinician cannot see, and the web renderer does not do it
/// either.
class OmfTabsLayout extends StatefulWidget {
  const OmfTabsLayout({required this.context, super.key});

  final RenderContext context;

  @override
  State<OmfTabsLayout> createState() => _OmfTabsLayoutState();
}

class _OmfTabsLayoutState extends State<OmfTabsLayout> {
  int _active = 0;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final pages = childElements(widget.context.element);
    if (pages.isEmpty) return const SizedBox.shrink();

    final active = _active.clamp(0, pages.length - 1);

    return Padding(
      padding: EdgeInsets.only(bottom: theme.sectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (var i = 0; i < pages.length; i++)
                  _Tab(
                    label: _tabLabel(pages[i], i),
                    selected: i == active,
                    onTap: () => setState(() => _active = i),
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.all(theme.controlPadding),
            decoration: BoxDecoration(
              border: Border.all(color: theme.border, width: theme.borderWidth),
            ),
            child: DispatchRenderer(
              element: pages[active],
              path: widget.context.path,
              enabled: widget.context.enabled,
            ),
          ),
        ],
      ),
    );
  }

  String _tabLabel(Map<String, dynamic> page, int index) {
    final label = page['label'];
    if (label is String && label.isNotEmpty) return label;
    return 'Page ${index + 1}';
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: theme.controlPadding * 1.5,
          vertical: theme.controlPadding,
        ),
        decoration: BoxDecoration(
          color: selected ? theme.surface : theme.sectionBackground,
          border: Border(
            top: BorderSide(color: theme.border, width: theme.borderWidth),
            left: BorderSide(color: theme.border, width: theme.borderWidth),
            right: BorderSide(color: theme.border, width: theme.borderWidth),
            bottom: BorderSide(
              color: selected ? theme.accent : theme.border,
              width: selected ? 2 : theme.borderWidth,
            ),
          ),
        ),
        child: Text(
          label,
          style: selected
              ? theme.labelStyle.copyWith(color: theme.accent)
              : theme.labelStyle,
        ),
      ),
    );
  }
}
