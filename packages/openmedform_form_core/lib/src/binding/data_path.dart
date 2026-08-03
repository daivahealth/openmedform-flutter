/// Data binding — read and write response values by data path or UI scope.
///
/// Ported from `packages/form-core/src/binding/data-path.ts` at form-core
/// 32236d66e350f89d6c76f120007a705963fa3312.
///
/// Writes are immutable: [setValueAtPath] returns a copy cloned along the
/// mutated branch and leaves the input untouched. That is what lets the
/// renderer detect changes by value identity, and it keeps a form's data safe
/// to hold in widget state.
library;

import '../schema/pointer.dart';

/// Normalise a dotted string or an explicit segment list into segments.
///
/// Accepts `String` or `List<String>`; the TypeScript original takes a
/// `string | string[]` union, which Dart has no direct equivalent for.
List<String> toPathSegments(Object path) {
  if (path is String) {
    return path.split('.').where((segment) => segment.isNotEmpty).toList();
  }
  if (path is List) {
    return <String>[for (final Object? segment in path) '$segment'];
  }
  throw ArgumentError.value(
    path,
    'path',
    'a data path must be a String or a List<String>',
  );
}

/// Read the value at a data path; null when any segment is missing.
///
/// List segments are addressed by numeric index. JavaScript indexes arrays with
/// string keys, so the original walks into arrays without any special case;
/// Dart needs the parse made explicit. Record-table paths such as
/// `treatments.0.date` depend on this.
Object? getValueAtPath(Object? data, Object path) {
  final segments = toPathSegments(path);
  Object? current = data;

  for (final segment in segments) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }

  return current;
}

Map<String, dynamic> _cloneMap(Object? node) => node is Map
    ? <String, dynamic>{
        for (final entry in node.entries) '${entry.key}': entry.value,
      }
    : <String, dynamic>{};

/// Rebuild [node] with [value] written at `segments[i…]`.
Object? _writeInto(
  Object? node,
  List<String> segments,
  int i,
  Object? value,
) {
  if (i == segments.length) return value;

  final key = segments[i];
  final index = int.tryParse(key);

  // A numeric segment against an existing list addresses an element. The
  // TypeScript's plain-object check excludes arrays, so it would replace the
  // list with a map here — see the note in CONFORMANCE.md for why this port
  // does not copy that. Record-table cells write through paths that cross an
  // array, and losing the array would discard every other record.
  if (node is List && index != null && index >= 0) {
    final copy = List<Object?>.from(node);
    while (copy.length <= index) {
      copy.add(null);
    }
    copy[index] = _writeInto(copy[index], segments, i + 1, value);
    return copy;
  }

  final map = _cloneMap(node);
  map[key] = _writeInto(map[key], segments, i + 1, value);
  return map;
}

/// Return a copy of [data] with [value] set at the data path.
///
/// Intermediate objects are created as needed and existing branches are
/// shallow-cloned, so the input is never mutated. A path segment that is a
/// number and lands on an existing list addresses that element rather than
/// replacing the list.
Map<String, dynamic> setValueAtPath(
  Map<String, dynamic>? data,
  Object path,
  Object? value,
) {
  final segments = toPathSegments(path);
  final root = <String, dynamic>{...?data};
  if (segments.isEmpty) return root;

  final result = _writeInto(root, segments, 0, value);
  return result is Map<String, dynamic> ? result : root;
}

/// Rebuild [node] with `segments[i…]` removed.
Object? _removeFrom(Object? node, List<String> segments, int i) {
  final key = segments[i];
  final index = int.tryParse(key);
  final last = i == segments.length - 1;

  if (node is List && index != null) {
    if (index < 0 || index >= node.length) return node;
    final copy = List<Object?>.from(node);
    if (last) {
      copy.removeAt(index);
    } else {
      copy[index] = _removeFrom(copy[index], segments, i + 1);
    }
    return copy;
  }

  if (node is! Map) return node; // nothing to delete

  final map = _cloneMap(node);
  if (last) {
    map.remove(key);
  } else {
    if (!map.containsKey(key)) return node;
    map[key] = _removeFrom(map[key], segments, i + 1);
  }
  return map;
}

/// Return a copy of [data] with the value at the data path removed.
///
/// Removal is distinct from writing null: several controls delete keys rather
/// than storing a falsy value, and the difference is visible in the submitted
/// JSON. See ARCHITECTURE.md section 4.
Map<String, dynamic> deleteValueAtPath(
  Map<String, dynamic>? data,
  Object path,
) {
  final segments = toPathSegments(path);
  final root = <String, dynamic>{...?data};
  if (segments.isEmpty) return root;

  final result = _removeFrom(root, segments, 0);
  return result is Map<String, dynamic> ? result : root;
}

/// Read the value a UI control scope binds to.
Object? getValueAtScope(Object? data, String scope) =>
    getValueAtPath(data, scopeToDataPathSegments(scope));

/// Set the value a UI control scope binds to, immutably.
Map<String, dynamic> setValueAtScope(
  Map<String, dynamic>? data,
  String scope,
  Object? value,
) =>
    setValueAtPath(data, scopeToDataPathSegments(scope), value);
