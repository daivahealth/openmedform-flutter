/// Clinical scoring.
///
/// Ported from `packages/form-core/src/scoring/score.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// A scored form carries each tickable item's point value on the UI element
/// under `options.omf.points`. This module is the single source of truth for
/// turning those points plus the current response into a total: the renderers
/// use it for the live on-screen tally, and the server re-derives the same
/// items to compute the authoritative score on submission. Because both read
/// the same points off the same UI schema, the live aid and the stored score
/// cannot drift — which is exactly why this port must not drift either.
library;

import '../binding/data_path.dart';
import '../schema/pointer.dart';
import '../ui/ui_element.dart';

/// A single scored control discovered in the UI schema.
class ScoreItem {
  const ScoreItem({
    required this.scope,
    required this.path,
    required this.points,
    this.section,
  });

  /// JSON Forms scope, e.g. `#/properties/age/properties/age75plus`.
  final String scope;

  /// Dotted data path, e.g. `age.age75plus`.
  final String path;

  /// Points contributed when the control is ticked.
  final num points;

  /// Nearest ancestor Group label, used for per-section subtotals.
  final String? section;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'scope': scope,
        'path': path,
        'points': points,
        'section': section,
      };

  @override
  String toString() => 'ScoreItem($path, $points, section: $section)';
}

/// A risk-stratification band.
///
/// Matches when the total falls within `[minScore, maxScore]`; either bound may
/// be omitted, and both are inclusive.
class RiskBand {
  const RiskBand(
      {required this.label, this.minScore, this.maxScore, this.color});

  factory RiskBand.fromJson(Map<String, dynamic> json) => RiskBand(
        label: json['label'] as String,
        minScore: json['minScore'] as num?,
        maxScore: json['maxScore'] as num?,
        color: json['color'] as String?,
      );

  final String label;
  final num? minScore;
  final num? maxScore;
  final String? color;

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (minScore != null) 'minScore': minScore,
        if (maxScore != null) 'maxScore': maxScore,
        'label': label,
        if (color != null) 'color': color,
      };
}

class ScoreBreakdown {
  const ScoreBreakdown({
    required this.total,
    required this.bySection,
    this.riskLabel,
    this.riskColor,
  });

  final num total;

  /// Subtotal per section label; only sections with scored items appear.
  final Map<String, num> bySection;

  final String? riskLabel;
  final String? riskColor;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'total': total,
        'bySection': bySection,
        'riskLabel': riskLabel,
        'riskColor': riskColor,
      };

  @override
  String toString() =>
      'ScoreBreakdown(total: $total, bySection: $bySection, risk: $riskLabel)';
}

/// Read a numeric `options.omf.points` off a UI element.
num? _elementPoints(Map<String, dynamic> element) {
  final points = readOmf(element)?['points'];
  // Deliberately `is num`: Dart bools are not numbers, matching `typeof`.
  return points is num ? points : null;
}

/// Read the `options.omf.bands` risk table off a UI element.
List<RiskBand>? elementBands(Map<String, dynamic> element) {
  final bands = readOmf(element)?['bands'];
  if (bands is! List) return null;
  return bands
      .whereType<Map<String, dynamic>>()
      .map(RiskBand.fromJson)
      .toList();
}

String? _groupLabel(Map<String, dynamic> element) {
  final label = element['label'];
  return element['type'] == 'Group' && label is String ? label : null;
}

/// Walk a UI schema — a root element or a `{layout}` wrapper — collecting every
/// scored control, tagged with its nearest ancestor Group.
List<ScoreItem> collectScoreItems(Map<String, dynamic> uiSchema) {
  final layout = uiSchema['layout'];
  final root = layout is Map<String, dynamic> ? layout : uiSchema;
  final items = <ScoreItem>[];

  void walk(Map<String, dynamic> element, String? section) {
    final nextSection = _groupLabel(element) ?? section;
    final scope = element['scope'];
    final points = _elementPoints(element);

    if (scope is String && points != null) {
      items.add(
        ScoreItem(
          scope: scope,
          path: scopeToDataPath(scope),
          points: points,
          section: nextSection,
        ),
      );
    }

    for (final child in childElements(element)) {
      walk(child, nextSection);
    }
  }

  walk(root, null);
  return items;
}

/// Whether a stored value counts as ticked for scoring.
///
/// The accepted set is exact and narrower than it looks: `'yes'` counts,
/// `'YES'` does not. Widening it would silently change every score on every
/// form, so it is pinned by the scoring conformance fixtures.
bool isPresent(Object? value) {
  if (value is bool) return value;
  if (value == 1) return true;
  if (value == '1' || value == 'yes') return true;
  return value is num && value > 0;
}

/// Resolve the first band whose range contains [total].
RiskBand? stratify(num total, List<RiskBand>? bands) {
  if (bands == null || bands.isEmpty) return null;
  for (final band in bands) {
    final aboveMin = band.minScore == null || total >= band.minScore!;
    final belowMax = band.maxScore == null || total <= band.maxScore!;
    if (aboveMin && belowMax) return band;
  }
  return null;
}

/// Compute the grand total, per-section subtotals, and — when bands are
/// supplied — the risk label and colour.
ScoreBreakdown computeScore(
  List<ScoreItem> items,
  Object? data, [
  List<RiskBand>? bands,
]) {
  num total = 0;
  final bySection = <String, num>{};

  for (final item in items) {
    if (isPresent(getValueAtScope(data, item.scope))) {
      total += item.points;
      final section = item.section;
      if (section != null) {
        bySection[section] = (bySection[section] ?? 0) + item.points;
      }
    }
  }

  final band = stratify(total, bands);
  return ScoreBreakdown(
    total: total,
    bySection: bySection,
    riskLabel: band?.label,
    riskColor: band?.color,
  );
}

/// Derive items from a UI schema and compute in one call.
ScoreBreakdown scoreUiSchema(
  Map<String, dynamic> uiSchema,
  Object? data, [
  List<RiskBand>? bands,
]) =>
    computeScore(collectScoreItems(uiSchema), data, bands);
