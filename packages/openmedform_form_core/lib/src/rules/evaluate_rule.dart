/// Conditional-rule engine — evaluates an element's SHOW/HIDE/ENABLE/DISABLE
/// rule against the current response data.
///
/// Ported from `packages/form-core/src/rules/evaluate-rule.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// A condition is JSON Forms style: a `scope` into the data plus an optional
/// matching `schema`. It is active when the value at the scope satisfies that
/// schema. With no schema, it is active when a value is simply present.
///
/// Only leaf conditions exist — the platform does not use JSON Forms' composite
/// `AND`/`OR` conditions, so they are not supported here either.
library;

import '../binding/data_path.dart';
import '../schema/json_schema.dart';
import '../validation/validator.dart';

/// A rule's effect on the element carrying it.
enum RuleEffect { show, hide, enable, disable }

RuleEffect? _effectFrom(Object? raw) {
  switch (raw) {
    case 'SHOW':
      return RuleEffect.show;
    case 'HIDE':
      return RuleEffect.hide;
    case 'ENABLE':
      return RuleEffect.enable;
    case 'DISABLE':
      return RuleEffect.disable;
    default:
      return null;
  }
}

/// The visibility and enablement an element resolves to.
class ElementState {
  const ElementState({required this.visible, required this.enabled});

  /// The default for an element with no rule.
  static const ElementState visibleEnabled =
      ElementState(visible: true, enabled: true);

  final bool visible;
  final bool enabled;

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'visible': visible, 'enabled': enabled};

  @override
  bool operator ==(Object other) =>
      other is ElementState &&
      other.visible == visible &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(visible, enabled);

  @override
  String toString() => 'ElementState(visible: $visible, enabled: $enabled)';
}

/// True when the condition's scoped value satisfies its schema.
///
/// With no schema the condition asks only whether a value is present. Note what
/// counts as absent: null and the empty string. `false` and `0` are present —
/// a clinician answering "no" has answered.
bool evaluateCondition(
  Map<String, dynamic> condition,
  Object? data,
  OmfValidator validator,
) {
  final scope = condition['scope'];
  if (scope is! String) return false;

  final value = getValueAtScope(data, scope);

  final schema = condition['schema'];
  if (schema is! JsonSchema) {
    return value != null && value != '';
  }

  return validator.validate(schema, value).valid;
}

/// Resolve a single rule to a visibility and enablement decision.
ElementState evaluateRule(
  Map<String, dynamic> rule,
  Object? data,
  OmfValidator validator,
) {
  final condition = rule['condition'];
  if (condition is! Map<String, dynamic>) return ElementState.visibleEnabled;

  final active = evaluateCondition(condition, data, validator);

  switch (_effectFrom(rule['effect'])) {
    case RuleEffect.show:
      return ElementState(visible: active, enabled: true);
    case RuleEffect.hide:
      return ElementState(visible: !active, enabled: true);
    case RuleEffect.enable:
      return ElementState(visible: true, enabled: active);
    case RuleEffect.disable:
      return ElementState(visible: true, enabled: !active);
    case null:
      return ElementState.visibleEnabled;
  }
}

/// Resolve an element's effective state; elements without a rule are always
/// visible and enabled.
ElementState evaluateElementState(
  Map<String, dynamic> element,
  Object? data,
  OmfValidator validator,
) {
  final rule = element['rule'];
  if (rule is! Map<String, dynamic>) return ElementState.visibleEnabled;
  return evaluateRule(rule, data, validator);
}

/// One surviving child of a container, with its position in the original list.
class VisibleElement {
  const VisibleElement({
    required this.element,
    required this.index,
    required this.enabled,
  });

  final Map<String, dynamic> element;

  /// Index in the *original* list. Renderers key on this so a child that
  /// appears or disappears does not renumber — and therefore rebuild — its
  /// siblings.
  final int index;

  /// Parent enablement ANDed with this element's own `ENABLE`/`DISABLE` rule.
  final bool enabled;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'element': element,
        'index': index,
        'enabled': enabled,
      };

  @override
  String toString() => 'VisibleElement(index: $index, enabled: $enabled)';
}

/// Resolve the children a container should actually render.
///
/// Containers that dispatch each child through [evaluateElementState] get rule
/// handling for free. Some do not: a table row *is* the layout, so it never
/// reaches the dispatcher and a rule on it was silently ignored. Resolving rows
/// through here instead means a progressive-disclosure table — reveal Feature 2
/// once Feature 1 is present — behaves identically in Flutter, React, Angular
/// and on the server, because all four run this same evaluation.
List<VisibleElement> filterVisibleElements(
  List<Map<String, dynamic>>? elements,
  Object? data,
  OmfValidator validator, {
  bool parentEnabled = true,
}) {
  final visible = <VisibleElement>[];
  final source = elements ?? const <Map<String, dynamic>>[];

  for (var index = 0; index < source.length; index++) {
    final element = source[index];
    final state = evaluateElementState(element, data, validator);
    if (!state.visible) continue;
    visible.add(
      VisibleElement(
        element: element,
        index: index,
        enabled: parentEnabled && state.enabled,
      ),
    );
  }

  return visible;
}

/// True when any child carries a rule.
///
/// Lets a container skip per-element rule work when — as on most forms — no
/// child is conditional at all.
bool hasElementRules(List<Map<String, dynamic>>? elements) =>
    (elements ?? const <Map<String, dynamic>>[])
        .any((element) => element['rule'] != null);
