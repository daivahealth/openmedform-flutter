/// The choices of a single- or multi-select control: code, display label, and —
/// when scored — the points that choice contributes.
///
/// Ported from `packages/form-core/src/schema/enum-options.ts` at form-core
/// 4ce8e4e82a7e1115212a73feb91c482a78cd0757.
///
/// Both web renderers call this, so React and Angular cannot label the same
/// schema differently; the same argument brings it here rather than leaving
/// each Flutter control to resolve its own options.
///
/// A clinical schema stores stable, language-independent codes (`ALERT`, `NO`)
/// and displays something else. Three ways to say what:
///
///   1. `oneOf: [{const: 'NO', title: 'No'}]` — JSON Forms-native, the label
///      sits beside the value it names. Preferred.
///   2. `enum: ['NO']` + `options.omf.optionLabels: {NO: 'No'}` — for schemas
///      that already carry a plain enum.
///   3. neither — the code is shown verbatim. Never blank: a visible `NO` is a
///      fixable authoring mistake, an empty radio is a mystery.
library;

import '../ui/ui_element.dart';
import 'json_schema.dart';

/// One selectable choice.
class EnumOption {
  EnumOption({required this.value, required this.label, this.points})
      : code = '$value';

  /// The value written to the response, with its JSON type preserved.
  ///
  /// Upstream stores `String(const)`, so a numeric `enum` is submitted as a
  /// string there. That is a payload this platform's own schemas would reject —
  /// `type: integer` fails on `"1"` — so the type is kept here. See
  /// docs/CONFORMANCE.md; [code] is the portable half and is what scoring and
  /// the fixtures compare.
  final Object? value;

  /// [value] as the string upstream keys everything by.
  final String code;

  /// What a clinician reads. Falls back to [code].
  final String label;

  /// Points this choice contributes, when the control is scored.
  final num? points;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'code': code,
        'label': label,
        if (points != null) 'points': points,
      };

  @override
  bool operator ==(Object other) =>
      other is EnumOption &&
      other.value == value &&
      other.label == label &&
      other.points == points;

  @override
  int get hashCode => Object.hash(value, label, points);

  @override
  String toString() => 'EnumOption($value, "$label", points: $points)';
}

/// Read `options.omf.optionPoints` off a UI element — a code→points map for a
/// select whose *choice* carries the score.
Map<String, num>? elementOptionPoints(Map<String, dynamic>? element) {
  final raw = element == null ? null : readOmf(element)?['optionPoints'];
  if (raw is! Map) return null;
  return <String, num>{
    for (final entry in raw.entries)
      if (entry.value is num) '${entry.key}': entry.value as num,
  };
}

Map<String, String>? _optionLabels(Map<String, dynamic>? element) {
  final raw = element == null ? null : readOmf(element)?['optionLabels'];
  if (raw is! Map) return null;
  return <String, String>{
    for (final entry in raw.entries)
      if (entry.value is String) '${entry.key}': entry.value as String,
  };
}

/// The options of an enum control, in schema order.
///
/// Returns an empty list for a schema with neither `enum` nor `oneOf` — the
/// caller is then not looking at a single-select and should render its normal
/// control.
List<EnumOption> resolveEnumOptions(
  JsonSchema? schema,
  Map<String, dynamic>? element,
) {
  final labels = _optionLabels(element);
  final points = elementOptionPoints(element);

  EnumOption decorate(Object? value, String? title) {
    final code = '$value';
    return EnumOption(
      value: value,
      label:
          (title != null && title.isNotEmpty) ? title : (labels?[code] ?? code),
      points: points?[code],
    );
  }

  // `oneOf` wins: a title written next to its const is the most specific
  // statement of intent available.
  for (final keyword in const <String>['oneOf', 'anyOf']) {
    final branches = schema?[keyword];
    if (branches is! List || branches.isEmpty) continue;

    final options = <EnumOption>[];
    for (final branch in branches) {
      if (branch is! Map) continue;
      if (!branch.containsKey('const')) continue;
      final value = branch['const'];
      if (value is! String && value is! num) continue;
      final title = branch['title'];
      options.add(decorate(value, title is String ? title : null));
    }
    // Every branch must be a labelled constant; a mixed combinator is a schema
    // constraint, not a picker. (Upstream filters instead of bailing, but it
    // never meets the validation form — see docs/CONFORMANCE.md.)
    if (options.isNotEmpty && options.length == branches.length) return options;
  }

  final values = schema?.enumValues;
  if (values != null) {
    return <EnumOption>[
      for (final value in values)
        if (value is String || value is num) decorate(value, null),
    ];
  }

  return const <EnumOption>[];
}

/// The options of a multi-select — an array whose `items` carry the
/// `enum`/`oneOf`. Same resolution, applied to `items`.
List<EnumOption> resolveMultiEnumOptions(
  JsonSchema? schema,
  Map<String, dynamic>? element,
) {
  if (schema == null || !schema.hasType('array')) return const <EnumOption>[];
  return resolveEnumOptions(schema.items, element);
}
