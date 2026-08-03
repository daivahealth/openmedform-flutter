/// The single recursive entry point: resolve an element to a widget and build
/// it.
///
/// Rules are evaluated here, per build, rather than stored — see
/// ARCHITECTURE.md section 6. A `HIDE` collapses the subtree; a `DISABLE`
/// threads `enabled: false` down through [RenderContext].
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../store/form_store.dart';
import '../theme/omf_theme.dart';
import 'render_context.dart';

/// Makes the active registry available to the tree.
class OmfRegistryScope extends InheritedWidget {
  const OmfRegistryScope({
    required this.registry,
    required super.child,
    super.key,
  });

  final ControlRegistry<OmfWidgetBuilder> registry;

  static ControlRegistry<OmfWidgetBuilder> of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<OmfRegistryScope>();
    assert(scope != null, 'No OmfRegistryScope found in the widget tree.');
    return scope!.registry;
  }

  @override
  bool updateShouldNotify(OmfRegistryScope oldWidget) =>
      !identical(registry, oldWidget.registry);
}

/// Renders one UI schema element, resolving it through the registry.
class DispatchRenderer extends StatelessWidget {
  const DispatchRenderer({
    required this.element,
    required this.path,
    this.suppressLabel = false,
    this.enabled = true,
    this.schemaRoot,
    this.inMeasuredRow = false,
    super.key,
  });

  final Map<String, dynamic> element;
  final List<String> path;
  final bool suppressLabel;
  final bool enabled;

  /// See [RenderContext.inMeasuredRow].
  final bool inMeasuredRow;

  /// The schema scopes resolve against, when it is not the form's data schema.
  ///
  /// A record-table row renders its detail against the array's *item* schema,
  /// so `#/properties/date` inside a treatment day means the day's date, not a
  /// top-level field of the form.
  final JsonSchema? schemaRoot;

  @override
  Widget build(BuildContext context) {
    final store = FormScope.of(context);
    final registry = OmfRegistryScope.of(context);

    // Rules are derived, never stored: a second source of truth for visibility
    // is a second thing that can go stale.
    final state = evaluateElementState(element, store.data, store.validator);
    if (!state.visible) return const SizedBox.shrink();

    final scope = elementScope(element);
    final root = schemaRoot ?? store.definition.dataSchema;

    // Paths compose rather than replace. At the top level `path` is empty and
    // this is just the scope's own segments, but a record-table row arrives
    // with `['treatments', '0']` already accumulated and its detail controls
    // must land beneath it.
    final resolvedPath = scope == null
        ? path
        : <String>[...path, ...scopeToDataPathSegments(scope)];

    final fieldSchema =
        scope == null ? null : resolveSchemaAtScope(root, scope);

    final renderContext = RenderContext(
      element: element,
      store: store,
      path: resolvedPath,
      fieldSchema: fieldSchema,
      schemaRoot: root,
      suppressLabel: suppressLabel,
      inMeasuredRow: inMeasuredRow,
      enabled: enabled && state.enabled && !store.readOnly,
    );

    final builder = registry.resolve(
      element,
      ControlContext(dataSchema: root, fieldSchema: fieldSchema),
    );

    if (builder == null) return UnknownElementWidget(context: renderContext);
    return builder(renderContext);
  }
}

/// Shown when no registered control matches an element.
///
/// Deliberately loud. A silently dropped clinical field is the worst failure
/// this renderer has — it looks like a form that simply does not ask the
/// question. A visible placeholder is a bug report instead.
class UnknownElementWidget extends StatelessWidget {
  const UnknownElementWidget({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final type = context.type ?? 'unknown';
    final control = context.omf?['control'];
    final descriptor =
        control is String ? '$type · omf.control=$control' : type;

    return Container(
      margin: EdgeInsets.only(bottom: theme.fieldGap),
      padding: EdgeInsets.all(theme.controlPadding),
      decoration: BoxDecoration(
        border: Border.all(color: theme.danger, width: theme.borderWidth),
        borderRadius: BorderRadius.circular(theme.borderRadius),
        color: theme.sectionBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Unsupported element: $descriptor',
              style: theme.labelStyle.copyWith(color: theme.danger)),
          if (context.scope != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(context.scope!, style: theme.helpStyle),
            ),
        ],
      ),
    );
  }
}

/// Render every child of a layout element.
List<Widget> buildChildren(
  RenderContext context, {
  bool? suppressLabel,
}) =>
    childElements(context.element)
        .map(
          (child) => DispatchRenderer(
            element: child,
            path: context.path,
            suppressLabel: suppressLabel ?? context.suppressLabel,
            enabled: context.enabled,
            schemaRoot: context.schemaRoot,
            inMeasuredRow: context.inMeasuredRow,
          ),
        )
        .toList();
