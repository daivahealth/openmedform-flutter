/// Standard controls, dispatched by the resolved field schema type.
///
/// Ported from `omf-controls.tsx` in the React renderer.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';
import '../widgets/field_frame.dart';

/// A single-line text field.
class OmfTextControl extends StatefulWidget {
  const OmfTextControl(
      {required this.context, this.multiline = false, super.key});

  final RenderContext context;
  final bool multiline;

  @override
  State<OmfTextControl> createState() => _OmfTextControlState();
}

class _OmfTextControlState extends State<OmfTextControl> {
  late final TextEditingController _controller =
      TextEditingController(text: _valueText);

  String get _valueText {
    final value = widget.context.value;
    return value == null ? '' : '$value';
  }

  @override
  void didUpdateWidget(OmfTextControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt an external change — never fight the user's cursor while they
    // are typing into this very field.
    if (_controller.text != _valueText && !_focus.hasFocus) {
      _controller.text = _valueText;
    }
  }

  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final rows = _rows();

    return FieldFrame.forContext(
      widget.context,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.context.enabled,
        style: theme.bodyStyle,
        minLines: widget.multiline ? rows : 1,
        maxLines: widget.multiline ? null : 1,
        keyboardType:
            widget.multiline ? TextInputType.multiline : TextInputType.text,
        decoration: omfInputDecoration(theme),
        onChanged: (value) => widget.context.store
            .updateAt(widget.context.path, value.isEmpty ? null : value),
      ),
    );
  }

  int _rows() {
    final screen = widget.context.omf?['screen'];
    final rows = screen is Map ? screen['rows'] : null;
    return rows is num ? rows.toInt() : OmfTheme.of(context).textareaRows;
  }
}

/// A numeric field.
///
/// Emits `int`/`double`, never a `String`. A text field that forwarded its raw
/// value would silently change the submitted JSON type and fail server-side
/// validation on a field the clinician filled in correctly.
class OmfNumberControl extends StatefulWidget {
  const OmfNumberControl(
      {required this.context, required this.integer, super.key});

  final RenderContext context;
  final bool integer;

  @override
  State<OmfNumberControl> createState() => _OmfNumberControlState();
}

class _OmfNumberControlState extends State<OmfNumberControl> {
  late final TextEditingController _controller =
      TextEditingController(text: _valueText);
  final FocusNode _focus = FocusNode();

  String get _valueText {
    final value = widget.context.value;
    if (value == null) return '';
    if (value is int) return '$value';
    if (value is double && value == value.truncateToDouble()) {
      return '${value.toInt()}';
    }
    return '$value';
  }

  @override
  void didUpdateWidget(OmfNumberControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != _valueText && !_focus.hasFocus) {
      _controller.text = _valueText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);

    return FieldFrame.forContext(
      widget.context,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        enabled: widget.context.enabled,
        style: theme.bodyStyle,
        maxLines: 1,
        keyboardType: TextInputType.numberWithOptions(
          decimal: !widget.integer,
          signed: true,
        ),
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(
            widget.integer ? RegExp(r'[\d-]') : RegExp(r'[\d.\-eE]'),
          ),
        ],
        decoration: omfInputDecoration(theme),
        onChanged: (raw) {
          if (raw.isEmpty) {
            widget.context.store.updateAt(widget.context.path, null);
            return;
          }
          final parsed =
              widget.integer ? int.tryParse(raw) : double.tryParse(raw);
          // A half-typed value such as "-" parses to nothing. Leave the last
          // good value in place rather than writing a string the schema will
          // reject.
          if (parsed != null) {
            widget.context.store.updateAt(widget.context.path, parsed);
          }
        },
      ),
    );
  }
}

/// A checkbox, with the label beside it and an optional point badge.
class OmfBooleanControl extends StatelessWidget {
  const OmfBooleanControl({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final value = context.value == true;
    final points = context.omf?['points'];
    final label = context.suppressLabel
        ? null
        : controlLabel(context.element, fieldSchema: context.fieldSchema);

    return Padding(
      padding: EdgeInsets.only(bottom: theme.fieldGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: context.enabled
                      ? (next) =>
                          context.store.updateAt(context.path, next ?? false)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              if (label != null && label.isNotEmpty)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(label, style: theme.bodyStyle),
                  ),
                )
              else
                const Spacer(),
              if (points is num) ...<Widget>[
                const SizedBox(width: 6),
                PointBadge(points: points),
              ],
            ],
          ),
          if (context.errors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child:
                  Text(context.errors.first.message, style: theme.errorStyle),
            ),
        ],
      ),
    );
  }
}

/// A dropdown over the schema's `enum`.
///
/// Option text is the raw stable code, matching both web renderers. Stored
/// values are language-independent codes; translating them for display is a
/// platform-wide decision, not a renderer-local one.
class OmfEnumControl extends StatelessWidget {
  const OmfEnumControl({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final options = context.fieldSchema?.enumValues ?? const <Object?>[];
    final current = context.value;

    return FieldFrame.forContext(
      context,
      child: DropdownButtonFormField<Object?>(
        initialValue: options.contains(current) ? current : null,
        isExpanded: true,
        style: theme.bodyStyle,
        decoration: omfInputDecoration(theme),
        items: <DropdownMenuItem<Object?>>[
          const DropdownMenuItem<Object?>(child: Text('')),
          for (final option in options)
            DropdownMenuItem<Object?>(
              value: option,
              child: Text('$option', style: theme.bodyStyle),
            ),
        ],
        onChanged: context.enabled
            ? (value) => context.store.updateAt(context.path, value)
            : null,
      ),
    );
  }
}

/// A date field backed by the platform picker, stored as `yyyy-MM-dd`.
class OmfDateControl extends StatelessWidget {
  const OmfDateControl({required this.context, super.key});

  final RenderContext context;

  static String _format(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final raw = context.value;
    final text = raw is String ? raw : '';

    return FieldFrame.forContext(
      context,
      child: InkWell(
        onTap: context.enabled
            ? () async {
                final parsed = DateTime.tryParse(text);
                final picked = await showDatePicker(
                  context: buildContext,
                  initialDate: parsed ?? DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime(2200),
                );
                if (picked != null) {
                  context.store.updateAt(context.path, _format(picked));
                }
              }
            : null,
        child: InputDecorator(
          decoration: omfInputDecoration(theme).copyWith(
            suffixIcon: Icon(Icons.calendar_today, size: theme.bodySize),
          ),
          child: Text(
            text,
            style: theme.bodyStyle.copyWith(
              color: text.isEmpty ? theme.muted : theme.text,
            ),
          ),
        ),
      ),
    );
  }
}
