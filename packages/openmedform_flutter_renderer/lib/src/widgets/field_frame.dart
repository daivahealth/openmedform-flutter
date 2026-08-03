/// Shared label + control + error frame.
///
/// Ported from `field-frame.tsx` in the React renderer. Every control renders
/// through this so spacing and error presentation stay identical across
/// controls, and across renderers.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';

class FieldFrame extends StatelessWidget {
  const FieldFrame({
    required this.child,
    this.label,
    this.required = false,
    this.errors = const <ValidationError>[],
    this.points,
    this.dense = false,
    super.key,
  });

  /// Build a frame straight from a render context, resolving the label and
  /// errors the same way for every control.
  factory FieldFrame.forContext(
    RenderContext context, {
    required Widget child,
  }) {
    final omfPoints = context.omf?['points'];

    return FieldFrame(
      // A suppressed label means a table cell, where the column header already
      // names the field. Such a cell also has a fixed height, so the frame must
      // not add its usual spacing.
      dense: context.suppressLabel,
      label: context.suppressLabel
          ? null
          : controlLabel(context.element, fieldSchema: context.fieldSchema),
      required: context.isRequired,
      errors: context.errors.toList(),
      points: omfPoints is num ? omfPoints : null,
      child: child,
    );
  }

  final Widget child;
  final String? label;
  final bool required;
  final List<ValidationError> errors;

  /// A point value, rendered as a colour-coded badge beside the label.
  final num? points;

  /// Drop the label, error line and spacing — for a fixed-height table cell.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);
    final labelText = label;

    // In a cell there is no room for a label or an error line, and the frame's
    // own spacing would overflow the row. The error still reaches the clinician
    // on submit, where the server's response is mapped back onto fields.
    if (dense) return child;

    return Padding(
      padding: EdgeInsets.only(bottom: theme.fieldGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (labelText != null && labelText.isNotEmpty) ...<Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      text: labelText,
                      children: <InlineSpan>[
                        if (required)
                          TextSpan(
                            text: ' *',
                            style: TextStyle(color: theme.invalid),
                          ),
                      ],
                    ),
                    style: theme.labelStyle,
                  ),
                ),
                if (points != null) ...<Widget>[
                  const SizedBox(width: 6),
                  PointBadge(points: points!),
                ],
              ],
            ),
            const SizedBox(height: 4),
          ],
          child,
          if (errors.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(errors.first.message, style: theme.errorStyle),
          ],
        ],
      ),
    );
  }
}

/// A colour-coded point value, matching `pointColor` in both web renderers.
class PointBadge extends StatelessWidget {
  const PointBadge({required this.points, super.key});

  final num points;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);
    final colors = OmfTheme.pointColors(points);
    final text = points == points.roundToDouble()
        ? points.toInt().toString()
        : points.toString();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.helpStyle.copyWith(
          color: colors.foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The shared border and padding for text-like inputs.
InputDecoration omfInputDecoration(OmfTheme theme, {String? hintText}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(theme.borderRadius),
    borderSide: BorderSide(color: theme.border, width: theme.borderWidth),
  );

  return InputDecoration(
    isDense: true,
    hintText: hintText,
    filled: true,
    fillColor: theme.surface,
    contentPadding: EdgeInsets.symmetric(
      horizontal: theme.controlPadding,
      vertical: theme.controlPadding,
    ),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: theme.accent, width: theme.borderWidth + 1),
    ),
    disabledBorder: border,
  );
}
