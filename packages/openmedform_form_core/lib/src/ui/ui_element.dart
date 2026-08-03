/// Access helpers for UI schema elements.
///
/// The core treats a UI schema as decoded JSON (`Map<String, dynamic>`), the
/// same way the TypeScript does. The renderer parses these maps into typed
/// elements for dispatch, but the engine itself only ever needs to read a few
/// well-known keys, and staying on maps keeps the port a transliteration rather
/// than a redesign.
library;

/// Read the `options.omf` extension bag off an element.
///
/// Every OpenMedForm-specific behaviour hangs off this bag: the control
/// selector, point values, risk bands, table columns, and the screen/print
/// overrides.
Map<String, dynamic>? readOmf(Map<String, dynamic> element) {
  final options = element['options'];
  if (options is! Map) return null;
  final omf = options['omf'];
  return omf is Map<String, dynamic> ? omf : null;
}

/// The `options.omf.control` selector, when present.
String? omfControl(Map<String, dynamic> element) {
  final control = readOmf(element)?['control'];
  return control is String ? control : null;
}

/// Child elements of a layout, or an empty list.
List<Map<String, dynamic>> childElements(Map<String, dynamic> element) {
  final elements = element['elements'];
  if (elements is! List) return const <Map<String, dynamic>>[];
  return elements.whereType<Map<String, dynamic>>().toList();
}

/// The element's `type` discriminator, e.g. `Control`, `Group`, `OmfTabsLayout`.
String? elementType(Map<String, dynamic> element) {
  final type = element['type'];
  return type is String ? type : null;
}

/// The element's `scope`, for control elements.
String? elementScope(Map<String, dynamic> element) {
  final scope = element['scope'];
  return scope is String ? scope : null;
}
