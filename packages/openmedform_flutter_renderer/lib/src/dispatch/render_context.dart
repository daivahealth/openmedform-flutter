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
    this.suppressLabel = false,
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

  /// Set by table layouts, whose header row already names the column.
  final bool suppressLabel;

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

    // Drop the trailing `properties/<name>` to reach the owning object.
    final ownerScope =
        '#/${segments.sublist(0, segments.length - 2).join('/')}';
    final owner = segments.length == 2
        ? store.definition.dataSchema
        : resolveSchemaAtScope(store.definition.dataSchema, ownerScope);

    return owner?.requiredProperties.contains(segments.last) ?? false;
  }

  RenderContext copyWith({
    Map<String, dynamic>? element,
    List<String>? path,
    JsonSchema? fieldSchema,
    bool? suppressLabel,
    bool? enabled,
  }) =>
      RenderContext(
        element: element ?? this.element,
        store: store,
        path: path ?? this.path,
        fieldSchema: fieldSchema ?? this.fieldSchema,
        suppressLabel: suppressLabel ?? this.suppressLabel,
        enabled: enabled ?? this.enabled,
      );
}

/// Builds the widget for an element.
typedef OmfWidgetBuilder = Widget Function(RenderContext context);
