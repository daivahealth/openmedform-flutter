/// A checkbox group bound to a single array property.
///
/// The platform emits two different shapes for "tick all that apply", and they
/// are not interchangeable:
///
/// - **One boolean per option.** `valuablesHeld.dentures`, `.hearingAid`, … each
///   a `boolean` with its own `Control`. Rendered by the ordinary boolean
///   control, one per element.
/// - **One array of codes.** `valuablesHeld.valuables` typed
///   `array` of `items.enum`, with a *single* `Control` for the whole group.
///   That is this control.
///
/// JSON Forms calls the second a multi-enum, and its vanilla renderers handle
/// it — which is why such a form renders on the web but, until now, reported
/// every one of these as an unsupported element here.
///
/// The stored value is a list of the selected codes in *schema* order, not the
/// order they were ticked, so two clinicians who tick the same boxes in a
/// different sequence produce byte-identical answers. Both web renderers do the
/// same; ADR-003 makes matching value derivation a safety requirement rather
/// than a nicety. An emptied group removes the property rather than storing
/// `[]`, for the same reason a cleared text field is removed: `required` checks
/// key presence.
library;

import 'package:flutter/material.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

import '../dispatch/render_context.dart';
import '../theme/omf_theme.dart';
import '../widgets/field_frame.dart';

class OmfMultiEnumControl extends StatelessWidget {
  const OmfMultiEnumControl({required this.context, super.key});

  final RenderContext context;

  List<Object?> get _selected {
    final value = context.value;
    return value is List ? List<Object?>.from(value) : const <Object?>[];
  }

  void _toggle(List<EnumOption> options, Object? option, bool checked) {
    final selected = _selected.toSet();
    if (checked) {
      selected.add(option);
    } else {
      selected.remove(option);
    }

    // Rebuilt from the schema's own order rather than mutated in place, so the
    // stored list never depends on the sequence of taps. A stored code that is
    // no longer an option falls out here, which is what the web renderers do
    // with it too.
    final next = <Object?>[
      for (final candidate in options)
        if (selected.contains(candidate.value)) candidate.value,
    ];

    if (next.isEmpty) {
      context.store.removeAt(context.path);
    } else {
      context.store.updateAt(context.path, next);
    }
  }

  @override
  Widget build(BuildContext buildContext) {
    final theme = OmfTheme.of(buildContext);
    final options =
        resolveMultiEnumOptions(context.fieldSchema, context.element);
    final selected = _selected;

    if (options.isEmpty) {
      return FieldFrame.forContext(
        context,
        child: Text(
          'No options defined for this field.',
          style: theme.helpStyle,
        ),
      );
    }

    return FieldFrame.forContext(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final option in options)
            _MultiEnumOption(
              label: option.label,
              checked: selected.contains(option.value),
              enabled: context.enabled,
              onChanged: (checked) => _toggle(options, option.value, checked),
            ),
        ],
      ),
    );
  }
}

class _MultiEnumOption extends StatelessWidget {
  const _MultiEnumOption({
    required this.label,
    required this.checked,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = OmfTheme.of(context);

    return InkWell(
      // The web wraps each option in a <label>, so its text is part of the tap
      // target. Reproduce that rather than making clinicians hit the box.
      onTap: enabled ? () => onChanged(!checked) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                onChanged: enabled ? (next) => onChanged(next ?? false) : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(label, style: theme.bodyStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
