/// Shared table chrome for the clinical controls.
///
/// The web renderers style every clinical table identically — a collapsed
/// 1px border, 8px cell padding, left-aligned body text — so that lives in one
/// place here rather than being repeated per control.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/omf_theme.dart';

/// One cell's content plus its alignment.
class OmfCell {
  const OmfCell(
    this.child, {
    this.align = TextAlign.left,
    this.background,
    this.columnSpan = 1,
    this.bold = false,
  });

  /// A text cell, styled with the body scale.
  factory OmfCell.text(
    String text, {
    TextAlign align = TextAlign.left,
    Color? background,
    int columnSpan = 1,
    bool bold = false,
  }) =>
      OmfCell(
        _CellText(text: text, align: align, bold: bold),
        align: align,
        background: background,
        columnSpan: columnSpan,
        bold: bold,
      );

  final Widget child;
  final TextAlign align;
  final Color? background;

  /// Cells spanning more than one column, for domain headings and footers.
  final int columnSpan;
  final bool bold;
}

class _CellText extends StatelessWidget {
  const _CellText(
      {required this.text, required this.align, required this.bold});

  final String text;
  final TextAlign align;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);
    return Text(
      text,
      textAlign: align,
      style: bold
          ? theme.bodyStyle.copyWith(fontWeight: FontWeight.w700)
          : theme.bodyStyle,
    );
  }
}

/// A bordered table.
///
/// Built from [Row]s inside a [Column] rather than Flutter's [Table], because
/// [Table] cannot span columns and several of these controls need a full-width
/// heading or footer row.
class OmfTable extends StatelessWidget {
  const OmfTable({
    required this.rows,
    this.columnWidths,
    this.scrollHorizontally = false,
    this.minWidth,
    super.key,
  });

  /// Rows of cells. A header row is just a row of bold cells.
  final List<List<OmfCell>> rows;

  /// Optional flex weights per column. Defaults to equal weight.
  final List<int>? columnWidths;

  /// Wrap in a horizontal scroll view, matching `overflow-x: auto` on the web.
  final bool scrollHorizontally;

  /// Minimum width when scrolling horizontally.
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);
    final side = BorderSide(color: theme.border, width: theme.borderWidth);

    // Columns are sized explicitly rather than with Expanded. A horizontally
    // scrolling table is laid out under unbounded width, where a flex child
    // cannot resolve — so the total width is decided here, outside the scroll
    // view, and each cell gets a concrete width.
    return LayoutBuilder(
      builder: (_, constraints) {
        final available =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
        final total = scrollHorizontally
            ? math.max(minWidth ?? available, available)
            : available;

        final columnCount = rows.fold<int>(
          0,
          (widest, row) => math.max(
            widest,
            row.fold<int>(0, (sum, cell) => sum + cell.columnSpan),
          ),
        );
        if (columnCount == 0 || total <= 0) return const SizedBox.shrink();

        final weights = <int>[
          for (var i = 0; i < columnCount; i++)
            columnWidths != null && i < columnWidths!.length
                ? columnWidths![i]
                : 1,
        ];
        final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
        final unit = total / totalWeight;

        final table = SizedBox(
          width: total,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final row in rows)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _cells(row, side, theme, weights, unit),
                  ),
                ),
            ],
          ),
        );

        final bordered = DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.border, width: theme.borderWidth),
          ),
          child: table,
        );

        if (!scrollHorizontally) return bordered;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: bordered,
        );
      },
    );
  }

  List<Widget> _cells(
    List<OmfCell> row,
    BorderSide side,
    OmfTheme theme,
    List<int> weights,
    double unit,
  ) {
    final cells = <Widget>[];

    var column = 0;
    for (var i = 0; i < row.length; i++) {
      final cell = row[i];

      // A spanning cell takes the combined width of the columns it covers.
      var weight = 0;
      for (var c = column; c < column + cell.columnSpan; c++) {
        weight += c < weights.length ? weights[c] : 1;
      }
      column += cell.columnSpan;

      cells.add(
        SizedBox(
          width: weight * unit,
          child: Container(
            padding: EdgeInsets.all(theme.controlPadding),
            decoration: BoxDecoration(
              color: cell.background,
              border: Border(
                left: i == 0 ? BorderSide.none : side,
                bottom: side,
              ),
            ),
            alignment: switch (cell.align) {
              TextAlign.center => Alignment.center,
              TextAlign.right => Alignment.centerRight,
              _ => Alignment.centerLeft,
            },
            child: cell.child,
          ),
        ),
      );
    }

    return cells;
  }
}
