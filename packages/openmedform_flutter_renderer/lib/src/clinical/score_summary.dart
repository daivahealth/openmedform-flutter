/// `scoreSummary` — a live, cross-section total for scored checklists.
///
/// Ported from `score-controls.tsx` in the React renderer.
///
/// The one control that reads the *whole* form: it walks the root UI schema for
/// every `options.omf.points` and sums them against the entire response, via
/// form-core's single scoring source of truth. The total shown here is a
/// clinician aid — the server recomputes the authoritative score on submission,
/// and client totals are never accepted.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';
import 'clinical_controls.dart' show parseCssColor;

class OmfScoreSummary extends StatelessWidget {
  const OmfScoreSummary({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final store = context.store;

    final rawBands = context.omf?['bands'];
    final bands = rawBands is List
        ? rawBands
            .whereType<Map<String, dynamic>>()
            .map(RiskBand.fromJson)
            .toList()
        : null;

    // The root layout, not this element — the total spans every section.
    final breakdown = scoreUiSchema(store.definition.layout, store.data, bands);
    final sections = breakdown.bySection.entries.toList();

    final label =
        controlLabel(context.element, fieldSchema: context.fieldSchema);
    final riskColor = breakdown.riskColor == null
        ? null
        : parseCssColor(breakdown.riskColor!);

    return Container(
      margin: EdgeInsets.only(bottom: theme.sectionGap),
      decoration: BoxDecoration(
        border: Border.all(color: theme.border, width: theme.borderWidth),
        borderRadius: BorderRadius.circular(theme.borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(theme.controlPadding),
            decoration: BoxDecoration(
              color: theme.sectionBackground,
              border: Border(
                bottom:
                    BorderSide(color: theme.border, width: theme.borderWidth),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    label.isEmpty ? 'Total Score' : label,
                    style: theme.labelStyle,
                  ),
                ),
                Text(
                  '${breakdown.total}',
                  style: theme.bodyStyle.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                if (breakdown.riskLabel != null) ...<Widget>[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: riskColor ?? theme.label),
                      color: (riskColor ?? theme.label).withValues(alpha: 0.13),
                    ),
                    child: Text(
                      breakdown.riskLabel!,
                      style: theme.helpStyle.copyWith(
                        color: riskColor ?? theme.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final section in sections)
            Padding(
              padding: EdgeInsets.all(theme.controlPadding),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      section.key,
                      style: theme.bodyStyle.copyWith(color: theme.label),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      '${section.value}',
                      textAlign: TextAlign.right,
                      style:
                          theme.bodyStyle.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(theme.controlPadding),
            child: Text(
              'Live total — the server recalculates the authoritative score on '
              'submission.',
              style: theme.helpStyle,
            ),
          ),
        ],
      ),
    );
  }
}
