/// A minimal port of JSON Forms' `Generate.uiSchema`.
///
/// Only the record table needs this: when an author supplies no
/// `options.detail` for a repeating log, the panel has to be generated from the
/// item schema or the row would open onto nothing.
///
/// Deliberately a subset. JSON Forms' generator handles combinators, tuples and
/// `$ref` chains; this handles objects, nested objects, and everything else as a
/// plain control — which is the shape record items actually take. Anything it
/// does not model still renders, because an unmatched element becomes a visible
/// placeholder rather than disappearing.
library;

import '../schema/json_schema.dart';
import '../schema/labels.dart';

/// Generate a layout covering every property of [schema].
///
/// [scopePrefix] is the pointer these properties hang off, so a nested object's
/// controls address the full path rather than a bare property name.
Map<String, dynamic> generateUiSchema(
  JsonSchema? schema, {
  String layoutType = 'VerticalLayout',
  String scopePrefix = '#',
}) {
  final elements = <Map<String, dynamic>>[];
  final properties = schema?['properties'];

  if (properties is Map) {
    for (final entry in properties.entries) {
      final key = '${entry.key}';
      final property = entry.value;
      if (property is! Map<String, dynamic>) continue;

      final scope = '$scopePrefix/properties/$key';

      // A nested object becomes a labelled group so the panel keeps the
      // schema's shape instead of flattening into an undifferentiated list.
      final nested = property['properties'];
      if (property['type'] == 'object' && nested is Map && nested.isNotEmpty) {
        final group = generateUiSchema(property, scopePrefix: scope);
        elements.add(<String, dynamic>{
          'type': 'Group',
          'label': property.title ?? labelFromKey(key),
          'elements': group['elements'],
        });
        continue;
      }

      elements.add(<String, dynamic>{'type': 'Control', 'scope': scope});
    }
  }

  return <String, dynamic>{'type': layoutType, 'elements': elements};
}
