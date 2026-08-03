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

/// Return a copy of [data] with [value] set at the data path.
///
/// Intermediate objects are created as needed and existing branches are
/// shallow-cloned, so the input is never mutated.
///
/// Note the inherited limitation: an intermediate that is a *list* is replaced
/// by a map rather than indexed into, because the original's plain-object check
/// excludes arrays. Writing into an array element needs the array rebuilt by
/// the caller. This is faithful to the TypeScript, and is a trap worth
/// remembering when the record table lands.
Map<String, dynamic> setValueAtPath(
  Map<String, dynamic>? data,
  Object path,
  Object? value,
) {
  final segments = toPathSegments(path);
  final root = <String, dynamic>{...?data};
  if (segments.isEmpty) return root;

  var cursor = root;
  for (var i = 0; i < segments.length - 1; i++) {
    final key = segments[i];
    final existing = cursor[key];
    final next = existing is Map
        ? <String, dynamic>{
            for (final entry in existing.entries) '${entry.key}': entry.value,
          }
        : <String, dynamic>{};
    cursor[key] = next;
    cursor = next;
  }

  cursor[segments.last] = value;
  return root;
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

  var cursor = root;
  for (var i = 0; i < segments.length - 1; i++) {
    final key = segments[i];
    final existing = cursor[key];
    if (existing is! Map) return root; // nothing to delete
    final next = <String, dynamic>{
      for (final entry in existing.entries) '${entry.key}': entry.value,
    };
    cursor[key] = next;
    cursor = next;
  }

  cursor.remove(segments.last);
  return root;
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
