/// Label resolution for a control.
///
/// Ported from `controlLabel` in `packages/form-print-engine/src/render-html.ts`
/// at form-core 32236d66e350f89d6c76f120007a705963fa3312.
///
/// ## A caution about humanisation
///
/// There is no single humanisation rule upstream. Three coexist, and they
/// disagree on inputs that contain digits or more than one word:
///
/// | source | `insertedBy` | `spo2Reading` |
/// |---|---|---|
/// | this file (print engine `controlLabel`) | `Inserted By` | `Spo2Reading` |
/// | `humanizeRecordKey` (record-table columns) | `Inserted by` | `Spo2 reading` |
/// | lodash `startCase` (what JSON Forms itself applies) | `Inserted By` | `Spo 2 Reading` |
///
/// The differences are real upstream behaviour, not an artefact of porting, and
/// they only surface for a property with no `title`. Nearly every generated
/// schema does carry a `title` — the golden form relies on it to keep English
/// out of a Greek form — so this is a fallback path, not the common one.
///
/// [labelFromKey] reproduces the print engine's rule. Which rule the *renderer*
/// should use is deliberately left to M3 (#4), where it can be settled against
/// what the React renderer actually displays rather than guessed here.
library;

import 'json_schema.dart';
import 'pointer.dart';

/// Humanise a property key the way the print engine does: split camelCase on a
/// lower-to-upper boundary and capitalise the first character, leaving the rest
/// of the casing alone.
///
/// Note the boundary regex excludes digits, so `spo2Reading` is left unsplit.
String labelFromKey(String key) {
  final spaced = key.replaceAllMapped(
    RegExp('([a-z])([A-Z])'),
    (match) => '${match[1]} ${match[2]}',
  );

  if (spaced.isEmpty) return spaced;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Resolve the visible label for a control element.
///
/// The chain is: an explicit string `label` on the element, then the resolved
/// field schema's `title`, then the humanised last segment of the scope. An
/// empty `title` falls through, matching the original's truthiness check.
String controlLabel(
  Map<String, dynamic> element, {
  JsonSchema? fieldSchema,
}) {
  final label = element['label'];
  if (label is String) return label;

  final title = fieldSchema?['title'];
  if (title is String && title.isNotEmpty) return title;

  final scope = element['scope'];
  if (scope is! String) return '';

  final segments = scopeToDataPathSegments(scope);
  return labelFromKey(segments.isEmpty ? '' : segments.last);
}
