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
        // A measured table row has a fixed height, so an unbounded textarea
        // would overflow it. Cap it at its configured rows there; elsewhere it
        // grows with the text, as on the web.
        maxLines:
            widget.multiline ? (widget.context.inMeasuredRow ? rows : null) : 1,
        keyboardType: _keyboardType(),
        decoration: omfInputDecoration(theme),
        onChanged: (value) {
          // A cleared field is *removed*, not stored as null. The web sets
          // `undefined`, which vanishes from the submitted JSON entirely — and
          // `required` treats an absent key differently from a null one, so
          // writing null here would change the server's verdict.
          if (value.isEmpty) {
            widget.context.store.removeAt(widget.context.path);
          } else {
            widget.context.store.updateAt(widget.context.path, value);
          }
        },
      ),
    );
  }

  /// `format: email` changes only the keyboard offered, never the stored
  /// value — the web does the same with `<input type="email">`, and the server
  /// stays the authority on whether an address is acceptable. Treating it as a
  /// distinct control instead would put a second string field in the registry
  /// for no behavioural gain.
  TextInputType _keyboardType() {
    if (widget.multiline) return TextInputType.multiline;
    return widget.context.fieldSchema?['format'] == 'email'
        ? TextInputType.emailAddress
        : TextInputType.text;
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
            // Removed rather than nulled — see the text control above.
            widget.context.store.removeAt(widget.context.path);
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
    final options = context.fieldSchema?.options ?? const <SchemaOption>[];
    final current = context.value;

    return FieldFrame.forContext(
      context,
      child: DropdownButtonFormField<Object?>(
        initialValue:
            options.any((option) => option.value == current) ? current : null,
        isExpanded: true,
        style: theme.bodyStyle,
        decoration: omfInputDecoration(theme),
        items: <DropdownMenuItem<Object?>>[
          const DropdownMenuItem<Object?>(child: Text('')),
          for (final option in options)
            DropdownMenuItem<Object?>(
              value: option.value,
              // `oneOf` carries a title; a bare `enum` does not, and there the
              // code is what the web renderers display too.
              child: Text(option.label, style: theme.bodyStyle),
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

  @override
  Widget build(BuildContext buildContext) => _TemporalField(
        context: context,
        icon: Icons.calendar_today,
        onPick: (host) async {
          final picked = await showDatePicker(
            context: host,
            initialDate:
                DateTime.tryParse(_temporalText(context)) ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (picked != null) {
            context.store.updateAt(context.path, _isoDate(picked));
          }
        },
      );
}

/// A `format: time` field, stored as `HH:mm`.
///
/// The web renderers hand these to `<input type="time">`, which submits
/// `HH:mm` — so that is what this writes, 24-hour and zero-padded, whatever
/// the device's clock display happens to be. A clinical form's time fields are
/// heavily used (the F273 transfer form alone has five), and free text is both
/// slower to fill and impossible to validate.
class OmfTimeControl extends StatelessWidget {
  const OmfTimeControl({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) => _TemporalField(
        context: context,
        icon: Icons.schedule,
        onPick: (host) async {
          final picked = await showTimePicker(
            context: host,
            initialTime: _parseTime(_temporalText(context)) ?? TimeOfDay.now(),
          );
          if (picked != null) {
            context.store.updateAt(
              context.path,
              _isoTime(picked.hour, picked.minute),
            );
          }
        },
      );
}

/// A `format: date-time` field, stored as `yyyy-MM-ddTHH:mm`.
///
/// Local time with no zone suffix, matching what `<input type="datetime-local">`
/// submits on the web. Appending a `Z` or an offset here would make the same
/// answer serialize differently across renderers, which ADR-003 forbids.
class OmfDateTimeControl extends StatelessWidget {
  const OmfDateTimeControl({required this.context, super.key});

  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) => _TemporalField(
        context: context,
        icon: Icons.event,
        onPick: (host) async {
          final existing = DateTime.tryParse(_temporalText(context));

          final date = await showDatePicker(
            context: host,
            initialDate: existing ?? DateTime.now(),
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (date == null || !host.mounted) return;

          final time = await showTimePicker(
            context: host,
            initialTime: existing == null
                ? TimeOfDay.now()
                : TimeOfDay(hour: existing.hour, minute: existing.minute),
          );
          // Backing out of the time half leaves the old value alone rather
          // than writing a date with an invented midnight.
          if (time == null) return;

          context.store.updateAt(
            context.path,
            '${_isoDate(date)}T${_isoTime(time.hour, time.minute)}',
          );
        },
      );
}

/// Shared presentation for the tap-to-pick temporal controls: the stored text
/// in a bordered box with a trailing icon, disabled when the form is read-only.
class _TemporalField extends StatelessWidget {
  const _TemporalField({
    required this.context,
    required this.icon,
    required this.onPick,
  });

  final RenderContext context;
  final IconData icon;
  final Future<void> Function(BuildContext host) onPick;

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final text = _temporalText(context);

    return FieldFrame.forContext(
      context,
      child: InkWell(
        onTap: context.enabled ? () => onPick(buildContext) : null,
        child: InputDecorator(
          decoration: omfInputDecoration(theme).copyWith(
            suffixIcon: Icon(icon, size: theme.bodySize),
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

/// The bound value as text. Anything that is not a string is treated as empty
/// rather than coerced — a temporal field holding a number is bad data, and
/// printing it would disguise that.
String _temporalText(RenderContext context) {
  final value = context.value;
  return value is String ? value : '';
}

String _isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _isoTime(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// Read `HH:mm` back out of a stored value so the picker opens where the
/// clinician left it. Seconds are tolerated on the way in (a server or an
/// older form may carry them) but never written back.
TimeOfDay? _parseTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return TimeOfDay(hour: hour, minute: minute);
}
