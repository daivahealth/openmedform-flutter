/// The renderer's public entry point.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import 'dispatch/default_registry.dart';
import 'dispatch/dispatcher.dart';
import 'dispatch/render_context.dart';
import 'store/form_store.dart';
import 'theme/omf_theme.dart';

/// Renders an OpenMedForm definition as a fillable widget tree.
///
/// Transport-free by design: it is handed a definition and reports data back
/// through [onChange]. Fetching and submitting belong to the host, or to
/// `openmedform_api_client`.
///
/// ```dart
/// OmfFormRenderer(
///   definition: definition,
///   initialData: submission.data,
///   onChange: (data) => autosave(data),
/// )
/// ```
class OmfFormRenderer extends StatefulWidget {
  const OmfFormRenderer({
    required this.definition,
    this.initialData,
    this.onChange,
    this.readOnly = false,
    this.validator,
    this.registry,
    this.theme,
    this.padding,
    this.scrollable = true,
    super.key,
  });

  final OmfFormDefinition definition;

  /// Data to start from — a saved draft, or a completed submission for replay.
  final Map<String, dynamic>? initialData;

  /// Called after every change with the whole data object.
  final void Function(Map<String, dynamic> data)? onChange;

  /// Renders every control disabled. Use for submission replay.
  final bool readOnly;

  /// Defaults to [JsonSchemaValidator]. Local validation is advisory; the
  /// server re-validates on completion.
  final OmfValidator? validator;

  /// Defaults to [createDefaultRegistry]. Supply an extended registry to add or
  /// override controls.
  final ControlRegistry<OmfWidgetBuilder>? registry;

  /// Defaults to [OmfTheme.defaults], which matches the web renderers.
  final OmfTheme? theme;

  final EdgeInsetsGeometry? padding;

  /// Wrap the form in a scroll view. Turn off when embedding in a host that
  /// already scrolls.
  final bool scrollable;

  @override
  State<OmfFormRenderer> createState() => OmfFormRendererState();
}

class OmfFormRendererState extends State<OmfFormRenderer> {
  late FormStore _store;
  late ControlRegistry<OmfWidgetBuilder> _registry;

  /// The current form data, for a host that holds a [GlobalKey] to this state.
  Map<String, dynamic> get data => _store.data;

  @override
  void initState() {
    super.initState();
    _registry = widget.registry ?? createDefaultRegistry();
    _store = _createStore();
  }

  FormStore _createStore() => FormStore(
        definition: widget.definition,
        initialData: widget.initialData,
        validator: widget.validator,
        readOnly: widget.readOnly,
        onChange: widget.onChange,
      );

  @override
  void didUpdateWidget(OmfFormRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.registry != oldWidget.registry) {
      _registry = widget.registry ?? createDefaultRegistry();
    }

    // Rebuild the store only when the form itself changes. Rebuilding it
    // because `initialData` changed would discard whatever the clinician has
    // typed since — the host feeds edits back through onChange, not by
    // re-supplying initialData.
    if (!identical(widget.definition, oldWidget.definition) ||
        widget.readOnly != oldWidget.readOnly) {
      _store.dispose();
      _store = _createStore();
    }
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? const OmfTheme.defaults();
    final baseTheme = Theme.of(context);

    Widget body = Builder(
      builder: (inner) => DispatchRenderer(
        element: widget.definition.layout,
        path: const <String>[],
      ),
    );

    final padding = widget.padding ?? EdgeInsets.all(theme.sectionPadding);
    body = Padding(padding: padding, child: body);

    if (widget.scrollable) {
      body = SingleChildScrollView(child: body);
    }

    // Replace any OmfTheme the host installed, keeping its other extensions.
    final List<ThemeExtension<dynamic>> extensions = baseTheme.extensions.values
        .where((ThemeExtension<dynamic> extension) => extension is! OmfTheme)
        .toList()
      ..add(theme);

    return Theme(
      data: baseTheme.copyWith(extensions: extensions),
      child: DefaultTextStyle(
        style: theme.bodyStyle,
        child: OmfRegistryScope(
          registry: _registry,
          child: FormScope(notifier: _store, child: body),
        ),
      ),
    );
  }
}
