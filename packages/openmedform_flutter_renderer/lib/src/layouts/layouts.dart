/// Standard JSON Forms layouts, plus the OpenMedForm extensions to Group.
///
/// Ported from `omf-controls.tsx` in the React renderer.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/dispatcher.dart';
import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';
import '../widgets/field_frame.dart';

/// A simple column of children.
Widget buildVerticalLayout(RenderContext context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: buildChildren(context),
    );

int? _childColSpan(Map<String, dynamic> child) {
  final screen = readOmf(child)?['screen'];
  if (screen is! Map) return null;
  final colSpan = screen['colSpan'];
  return colSpan is num ? colSpan.toInt() : null;
}

/// A row whose children may declare a `colSpan` out of twelve.
///
/// Below the small breakpoint the row stacks, matching the web renderer's
/// wrapping behaviour on a narrow viewport. [LayoutBuilder] rather than
/// [MediaQuery], so an embedded form reacts to the space it is actually given
/// rather than to the size of the screen.
class OmfHorizontalLayout extends StatelessWidget {
  const OmfHorizontalLayout({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final children = childElements(context.element);
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (_, constraints) {
        final stack = constraints.maxWidth < theme.smBreakpoint;

        final rendered = <Widget>[
          for (final child in children)
            DispatchRenderer(
              element: child,
              path: context.path,
              suppressLabel: context.suppressLabel,
              enabled: context.enabled,
            ),
        ];

        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rendered,
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var i = 0; i < rendered.length; i++) ...<Widget>[
              if (i > 0) SizedBox(width: theme.controlGap),
              Expanded(
                // colSpan is out of 12; a child without one shares the
                // remaining space equally, as `flex: 1 1 0` does on the web.
                flex: _childColSpan(children[i]) ?? 1,
                child: rendered[i],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Read-only instruction text.
///
/// Line breaks in the source are significant — a dash-bulleted list must stay
/// one item per line, as it is on the paper form. Flutter's [Text] preserves
/// `\n` natively, which is what the web renderer needs `white-space: pre-line`
/// for.
Widget buildLabelElement(RenderContext context) {
  final text = context.element['text'];
  if (text is! String || text.trim().isEmpty) return const SizedBox.shrink();

  return Builder(
    builder: (buildContext) {
      final theme = OmfTheme.of(buildContext);
      return Padding(
        padding: EdgeInsets.only(bottom: theme.fieldGap),
        child: Text(
          text,
          style: theme.bodyStyle.copyWith(height: 1.6, color: theme.label),
        ),
      );
    },
  );
}

/// A bordered section with a shaded header, or — with
/// `omf.variant: 'subsection'` — an indented heading with no box.
class OmfGroupLayout extends StatelessWidget {
  const OmfGroupLayout({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final omf = context.omf;

    final rawLabel = context.element['label'];
    final labelText = rawLabel is String ? rawLabel : '';

    final accentValue = omf?['accentColor'];
    final accent =
        accentValue is String ? _parseColor(accentValue) ?? theme.accent : null;
    final borderColor = accent ?? theme.border;

    final rawIcon = omf?['icon'];
    // Avoid a double glyph when the generator also embedded the icon in the
    // label text.
    final icon =
        rawIcon is String && !labelText.contains(rawIcon) ? rawIcon : null;

    final legendValue = omf?['pointLegend'];
    final legend =
        legendValue is List ? legendValue.whereType<num>().toList() : null;

    final children = buildChildren(context);

    // Live section subtotal: this box's own scored descendants, against the
    // whole form's data.
    final scoreItems = collectScoreItems(context.element);
    final subtotal = scoreItems.isEmpty
        ? null
        : computeScore(scoreItems, context.store.data).total;

    if (omf?['variant'] == 'subsection') {
      return Padding(
        padding: EdgeInsets.only(bottom: theme.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (labelText.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: theme.fieldGap),
                child: Text(labelText, style: theme.labelStyle),
              ),
            Container(
              margin: EdgeInsets.only(left: theme.subsectionIndent),
              padding: EdgeInsets.only(left: theme.controlPadding),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: borderColor, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: theme.borderWidth),
        borderRadius: BorderRadius.circular(theme.borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (labelText.isNotEmpty)
            Container(
              padding: EdgeInsets.all(theme.controlPadding),
              decoration: BoxDecoration(
                color: theme.sectionBackground,
                border: Border(
                  bottom:
                      BorderSide(color: borderColor, width: theme.borderWidth),
                ),
              ),
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Text(icon,
                        style: TextStyle(fontSize: theme.labelSize * 1.1)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      labelText,
                      style: theme.labelStyle
                          .copyWith(color: accent ?? theme.label),
                    ),
                  ),
                  if (legend != null && legend.isNotEmpty)
                    for (final points in legend)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: PointBadge(points: points),
                      ),
                  if (subtotal != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: borderColor),
                        ),
                        child: Text(
                          'Σ $subtotal',
                          style: theme.helpStyle.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.text,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(theme.controlPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Parse a `#rrggbb` or `#rgb` colour from the schema.
Color? _parseColor(String value) {
  var hex = value.trim().replaceFirst('#', '');
  if (hex.length == 3) {
    hex = hex.split('').map((char) => '$char$char').join();
  }
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;

  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? null : Color(parsed);
}
