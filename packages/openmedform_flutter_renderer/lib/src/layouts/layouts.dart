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

    final rendered = <Widget>[
      for (final child in children)
        DispatchRenderer(
          element: child,
          path: context.path,
          suppressLabel: context.suppressLabel,
          enabled: context.enabled,
          schemaRoot: context.schemaRoot,
          inMeasuredRow: context.inMeasuredRow,
        ),
    ];

    Widget row() => Row(
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

    // Inside a ruled table the row is measured for its intrinsic height, and
    // Flutter cannot measure through a LayoutBuilder. Cells are narrow anyway,
    // and the paper form they came from does not reflow, so stay a row.
    if (context.inMeasuredRow) return row();

    return LayoutBuilder(
      builder: (_, constraints) {
        if (constraints.maxWidth < theme.smBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: rendered,
          );
        }
        return row();
      },
    );
  }
}

/// Read-only instruction text — or, with an accent, a callout.
///
/// Line breaks in the source are significant — a dash-bulleted list must stay
/// one item per line, as it is on the paper form. Flutter's [Text] preserves
/// `\n` natively, which is what the web renderer needs `white-space: pre-line`
/// for.
///
/// With `omf.accentColor` the Label becomes the bordered, tinted, bold banner a
/// paper form puts around a result or a warning ("Overall result: CAM-ICU
/// POSITIVE"). The conversion pipeline emits computed clinical outcomes in
/// exactly that shape, and the whole point is that a clinician's eye lands on
/// the answer — as body text it reads like a footnote. Same key that already
/// colours a Group, so there is no new vocabulary, and a Label *without* an
/// accent is unchanged: existing instruction blocks are untouched.
Widget buildLabelElement(RenderContext context) {
  final text = context.element['text'];
  if (text is! String || text.trim().isEmpty) return const SizedBox.shrink();

  final omf = context.omf;
  final accentValue = omf?['accentColor'];
  final accent = accentValue is String ? omfAccentColor(accentValue) : null;

  final rawIcon = omf?['icon'];
  // Avoid a double glyph when the generator also embedded the icon in the text.
  final icon = rawIcon is String && !text.contains(rawIcon) ? rawIcon : null;

  return Builder(
    builder: (buildContext) {
      final theme = OmfTheme.of(buildContext);
      final body = theme.bodyStyle.copyWith(height: 1.6, color: theme.label);

      if (accentValue is! String) {
        return Padding(
          padding: EdgeInsets.only(bottom: theme.fieldGap),
          child: Text(text, style: body),
        );
      }

      // Degrade, don't break: an accent the colour maths cannot read (a CSS
      // variable, a named colour) still paints the border and the text in the
      // theme accent, and only the wash is skipped. A callout with no wash
      // still reads as a callout; a fallback to an unrelated colour would not.
      final border = accent ?? theme.accent;

      return Padding(
        padding: EdgeInsets.only(bottom: theme.fieldGap),
        child: Semantics(
          // The web callout is `role="status"`; this is its Flutter twin, so
          // the banner is announced as a result rather than read as ordinary
          // body text.
          liveRegion: true,
          container: true,
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: theme.controlPadding,
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              // 8% of the accent, matching form-core's `accentTint`. The
              // number matters more than the implementation: a result banner
              // appearing in a visibly different shade here than on the web is
              // exactly the cross-renderer drift the contract forbids.
              color: accent?.withValues(alpha: accentTintAlpha),
              border: Border.all(color: border, width: 2),
              borderRadius: BorderRadius.circular(theme.borderRadius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Text(icon, style: body),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    text,
                    style: body.copyWith(
                      color: border,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    final accent = accentValue is String
        ? omfAccentColor(accentValue) ?? theme.accent
        : null;
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
    // whole form's data — but only where a total belongs, which is the
    // innermost scoring section unless the definition says otherwise. Summing
    // every scored descendant grew a chip on every ancestor too, and a subtotal
    // on a box that merely *contains* scoring sections is noise at best; read
    // as a clinical total, it is wrong.
    final scoreItems = showsSectionSubtotal(context.element)
        ? collectScoreItems(context.element)
        : const <ScoreItem>[];

    // Bands on the *section* stratify that section's own subtotal, which is
    // what a sheet carrying several independent instruments needs: qSOFA is
    // positive at >= 2 of 3 and SIRS at >= 2 of 4, and a form-level
    // scoreSummary would add them into a number that means nothing clinically.
    final score = scoreItems.isEmpty
        ? null
        : computeScore(
            scoreItems,
            context.store.data,
            elementBands(context.element),
          );
    final subtotal = score?.total;
    final verdict = score?.riskLabel;
    final verdictColor =
        score?.riskColor == null ? null : omfAccentColor(score!.riskColor!);

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
                    _HeaderChip(
                      text: 'Σ $subtotal',
                      borderColor: borderColor,
                      textColor: theme.text,
                    ),
                  // The section's own verdict, beside its own total — so a
                  // clinician reads "Σ 2 Positive" without having to remember
                  // each instrument's threshold.
                  if (verdict != null)
                    _HeaderChip(
                      text: verdict,
                      borderColor: verdictColor ?? borderColor,
                      textColor: verdictColor ?? theme.text,
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

/// A pill in a Group header: the `Σ n` subtotal, or the section's verdict.
class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.text,
    required this.borderColor,
    required this.textColor,
  });

  final String text;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          text,
          style: theme.helpStyle.copyWith(
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// Resolve an `omf.accentColor` (or a band's `color`) to a [Color].
///
/// Parsing lives in form-core so this renderer accepts and rejects exactly what
/// the web renderers and the print engine do — a colour one surface paints and
/// another silently drops is the same drift as painting it a different shade.
Color? omfAccentColor(String? value) {
  final rgb = parseHexColor(value);
  if (rgb == null) return null;
  return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
}
