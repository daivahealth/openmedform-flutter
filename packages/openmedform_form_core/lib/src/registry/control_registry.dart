/// The framework-independent contract for mapping a UI schema element to the
/// renderer that should draw it.
///
/// Ported from `packages/form-core/src/registry/control-registry.ts` at
/// form-core 32236d66e350f89d6c76f120007a705963fa3312.
///
/// Matching follows JSON Forms' tester/rank idea: every entry's tester scores
/// an element, and the highest positive score wins. [notApplicable] means the
/// entry cannot render the element.
///
/// Upstream this registry is a contract that neither shipped renderer actually
/// uses — React and Angular both defer to JSON Forms' own `rankWith`. For a
/// renderer with no JSON Forms runtime it is the ready-made specification, so
/// here it is load-bearing rather than aspirational.
library;

import '../schema/json_schema.dart';
import '../ui/ui_element.dart';

/// Score meaning "this entry does not apply to this element".
const int notApplicable = -1;

/// Context a tester may consult.
class ControlContext {
  const ControlContext({this.dataSchema, this.fieldSchema});

  /// The whole data schema, for testers that need to resolve a reference.
  final JsonSchema? dataSchema;

  /// The schema of the field this element binds to, already resolved.
  final JsonSchema? fieldSchema;
}

/// Scores how well an entry matches an element. Higher wins; -1 means no match.
typedef ControlTester = int Function(
  Map<String, dynamic> element,
  ControlContext? context,
);

class RegistryEntry<R> {
  const RegistryEntry(this.tester, this.renderer);

  final ControlTester tester;
  final R renderer;
}

/// A generic, framework-agnostic control registry.
///
/// `R` is intentionally open: a widget builder here, a React component
/// upstream, a print handler in the print engine.
class ControlRegistry<R> {
  final List<RegistryEntry<R>> _entries = <RegistryEntry<R>>[];

  ControlRegistry<R> register(ControlTester tester, R renderer) {
    _entries.add(RegistryEntry<R>(tester, renderer));
    return this;
  }

  ControlRegistry<R> registerAll(Iterable<RegistryEntry<R>> entries) {
    _entries.addAll(entries);
    return this;
  }

  /// Resolve the best-matching renderer, or null when none applies.
  ///
  /// Ties go to the entry registered first, because a later entry must beat the
  /// incumbent outright (`rank > bestRank`). Registration order is therefore
  /// meaningful among equal ranks — the same rule the TypeScript follows.
  R? resolve(Map<String, dynamic> element, [ControlContext? context]) {
    R? best;
    var bestRank = notApplicable;

    for (final entry in _entries) {
      final rank = entry.tester(element, context);
      if (rank > bestRank) {
        bestRank = rank;
        best = entry.renderer;
      }
    }

    return bestRank > notApplicable ? best : null;
  }

  int get size => _entries.length;

  void clear() => _entries.clear();
}

// --- Tester factories -------------------------------------------------------
//
// The default ranks are part of the contract, not tuning knobs: a clinical
// control must outrank the generic control that would otherwise claim the same
// element.

/// Matches when `options.omf.control` equals [control]. Highest default rank.
ControlTester byOmfControl(String control, {int rank = 20}) =>
    (element, context) => omfControl(element) == control ? rank : notApplicable;

/// Matches a custom `Omf*` layout element by its `type`.
ControlTester byOmfLayout(String type, {int rank = 15}) =>
    (element, context) => element['type'] == type ? rank : notApplicable;

/// Matches a standard JSON Forms element `type` (`Control`, `Group`, …).
ControlTester byType(String type, {int rank = 5}) =>
    (element, context) => element['type'] == type ? rank : notApplicable;

/// Matches `Control` elements whose resolved field schema has a given type.
///
/// Honours a union `type` array, so `["string", "null"]` still matches
/// `string`.
ControlTester bySchemaType(String schemaType, {int rank = 8}) =>
    (element, context) {
      if (element['type'] != 'Control') return notApplicable;

      final type = context?.fieldSchema?['type'];
      final matches =
          type is List ? type.contains(schemaType) : type == schemaType;
      return matches ? rank : notApplicable;
    };
