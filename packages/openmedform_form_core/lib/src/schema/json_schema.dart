/// The JSON Schema representation used throughout the core.
///
/// Ported from `@openmedform/form-schema-types` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
library;

/// A JSON Schema node (Draft 2020-12), as decoded JSON.
///
/// Deliberately a plain map rather than a class hierarchy. JSON Schema is
/// open-ended — the TypeScript contract itself carries an index-signature
/// escape hatch — and every validator wants the raw map. Modelling it as Dart
/// classes would silently drop keywords we did not think to enumerate, which is
/// the one failure mode a validation layer must not have.
///
/// `uiSchema` is the opposite case and *is* modelled as classes: the renderer
/// switches on element type exhaustively, and there the compiler's help is
/// worth having.
typedef JsonSchema = Map<String, dynamic>;

/// Convenience reads over a schema node.
extension JsonSchemaX on JsonSchema {
  /// The `type` keyword when it is a single string, else null.
  ///
  /// Returns null for a union such as `["string", "null"]`; use [hasType] to
  /// ask whether a particular type is permitted.
  String? get schemaType {
    final value = this['type'];
    return value is String ? value : null;
  }

  /// Whether this node permits [type], accounting for union `type` arrays.
  bool hasType(String type) {
    final value = this['type'];
    if (value is String) return value == type;
    if (value is List) return value.contains(type);
    return false;
  }

  /// The `title` keyword — the primary human label, in the form's source
  /// language.
  String? get title => this['title'] is String ? this['title'] as String : null;

  /// Sub-schemas under `properties`, or an empty map.
  Map<String, dynamic> get properties {
    final value = this['properties'];
    return value is Map<String, dynamic> ? value : const <String, dynamic>{};
  }

  /// Property names listed under `required`.
  List<String> get requiredProperties {
    final value = this['required'];
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList();
  }

  /// The `items` sub-schema for an array node, if it is a single schema.
  JsonSchema? get items {
    final value = this['items'];
    return value is Map<String, dynamic> ? value : null;
  }

  /// The `$ref` target when this node is a reference.
  String? get ref => this[r'$ref'] is String ? this[r'$ref'] as String : null;

  /// Allowed values under `enum`, or null when the keyword is absent.
  List<Object?>? get enumValues {
    final value = this['enum'];
    return value is List ? List<Object?>.from(value) : null;
  }

  /// The selectable options this node describes, or null when it is not a
  /// choice.
  ///
  /// Covers both shapes the platform emits:
  ///
  /// - `enum: ["YES", "NO"]` — the stored code is also the label, which is what
  ///   the shipped web renderers display.
  /// - `oneOf: [{const: "CACHETIC", title: "Cachectic"}]` — a labelled choice.
  ///   The generator uses this whenever the display text differs from the
  ///   stored code, so ignoring `title` here would put `CACHETIC` in front of a
  ///   clinician.
  ///
  /// `anyOf` is accepted on the same terms; JSON Forms treats it identically
  /// for this purpose.
  List<SchemaOption>? get options {
    final enumerated = enumValues;
    if (enumerated != null) {
      return <SchemaOption>[
        for (final value in enumerated)
          SchemaOption(value: value, label: '$value'),
      ];
    }

    for (final keyword in const <String>['oneOf', 'anyOf']) {
      final branches = this[keyword];
      if (branches is! List) continue;

      final options = <SchemaOption>[];
      for (final branch in branches) {
        if (branch is! Map) continue;
        if (!branch.containsKey('const')) continue;
        final value = branch['const'];
        final title = branch['title'];
        options.add(
          SchemaOption(
            value: value,
            label: title is String && title.isNotEmpty ? title : '$value',
          ),
        );
      }
      // Every branch must be a labelled constant; a mixed combinator is a
      // schema constraint, not a picker.
      if (options.isNotEmpty && options.length == branches.length) {
        return options;
      }
    }

    return null;
  }

  /// The options of an array's items, when this node is a multi-select.
  List<SchemaOption>? get itemOptions {
    if (!hasType('array')) return null;
    final itemSchema = items;
    return itemSchema?.options;
  }
}

/// One selectable value and the text shown for it.
class SchemaOption {
  const SchemaOption({required this.value, required this.label});

  /// The value stored in the response — always the language-independent code.
  final Object? value;

  /// What a clinician reads.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SchemaOption && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'SchemaOption($value, "$label")';
}
