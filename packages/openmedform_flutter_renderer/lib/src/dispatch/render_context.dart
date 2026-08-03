/// Everything a control needs to render itself.
library;

import 'package:flutter/widgets.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../store/form_store.dart';

@immutable
class RenderContext {
  const RenderContext({
    required this.element,
    required this.store,
    required this.path,
    this.fieldSchema,
    this.schemaRoot,
    this.suppressLabel = false,
    this.inMeasuredRow = false,
    this.enabled = true,
  });

  /// The UI schema element being rendered.
  final Map<String, dynamic> element;

  final FormStore store;

  /// Composed data path segments, e.g. `['assessment', 'spo2']`.
  ///
  /// Record-table rows extend this with the row index, which is why it is
  /// segments rather than a dotted string.
  final List<String> path;

  /// The field's schema, already resolved through the element's scope.
  final JsonSchema? fieldSchema;

  /// The schema this element's scope was resolved against.
  ///
  /// The form's data schema, except inside a record-table row, where it is the
  /// array's item schema.
  final JsonSchema? schemaRoot;

  /// Set by table layouts, whose header row already names the column.
  final bool suppressLabel;

  /// True when an ancestor measures this subtree's intrinsic height.
  ///
  /// A table row sizes its cells with [IntrinsicHeight] so their borders line
  /// up, and Flutter cannot compute an intrinsic dimension through a
  /// [LayoutBuilder] — it would have to run the layout callback speculatively.
  /// Controls that would otherwise reach for `LayoutBuilder` check this flag
  /// and use a fixed arrangement instead.
  ///
  /// Real forms hit this constantly: the reference anaesthesia form nests 23
  /// horizontal layouts inside two ruled tables.
  final bool inMeasuredRow;

  /// False when an ancestor rule disabled this subtree, or the form is
  /// read-only.
  final bool enabled;

  /// The `options.omf` bag, if present.
  Map<String, dynamic>? get omf => readOmf(element);

  /// The element's `type` discriminator.
  String? get type => elementType(element);

  /// The element's `scope`, for control elements.
  String? get scope => elementScope(element);

  /// The current value at [path].
  Object? get value => store.valueAt(path);

  /// Validation errors bound to this field.
  Iterable<ValidationError> get errors => store.errorsAtPath(path);

  /// Whether the containing object marks this property required.
  bool get isRequired {
    final scope = this.scope;
    if (scope == null) return false;

    final segments = scopeToSchemaSegments(scope);
    if (segments.length < 2) return false;

    final root = schemaRoot ?? store.definition.dataSchema;

    // Drop the trailing `properties/<name>` to reach the owning object.
    final ownerScope =
        '#/${segments.sublist(0, segments.length - 2).join('/')}';
    final owner =
        segments.length == 2 ? root : resolveSchemaAtScope(root, ownerScope);

    return owner?.requiredProperties.contains(segments.last) ?? false;
  }

  RenderContext copyWith({
    Map<String, dynamic>? element,
    List<String>? path,
    JsonSchema? fieldSchema,
    bool? suppressLabel,
    bool? inMeasuredRow,
    bool? enabled,
  }) =>
      RenderContext(
        element: element ?? this.element,
        store: store,
        path: path ?? this.path,
        fieldSchema: fieldSchema ?? this.fieldSchema,
        schemaRoot: schemaRoot,
        suppressLabel: suppressLabel ?? this.suppressLabel,
        inMeasuredRow: inMeasuredRow ?? this.inMeasuredRow,
        enabled: enabled ?? this.enabled,
      );
}

/// Builds the widget for an element.
typedef OmfWidgetBuilder = Widget Function(RenderContext context);
