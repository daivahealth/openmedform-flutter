/// The renderer's single piece of state: the form's data, plus the errors
/// derived from it.
///
/// A plain [ChangeNotifier], deliberately — see ARCHITECTURE.md section 6. The
/// state here is one small atom, which is exactly what the JSON Forms store it
/// mirrors holds, and a reusable package should not conscript its host into a
/// state-management framework.
library;

import 'package:flutter/widgets.dart';
import 'package:openmedform_form_core/openmedform_form_core.dart';

class FormStore extends ChangeNotifier {
  FormStore({
    required this.definition,
    Map<String, dynamic>? initialData,
    OmfValidator? validator,
    this.readOnly = false,
    this.onChange,
  })  : validator = validator ?? JsonSchemaValidator(),
        _data = initialData == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(initialData) {
    _revalidate();
  }

  final OmfFormDefinition definition;
  final OmfValidator validator;

  /// Renders every control disabled, for submission replay.
  final bool readOnly;

  /// Called after each change, with the new data. The seam a host autosaves on.
  final void Function(Map<String, dynamic> data)? onChange;

  Map<String, dynamic> _data;
  ValidationResult _validation = const ValidationResult.ok();

  /// The current form data. Treat as immutable — replace via [updateAt].
  Map<String, dynamic> get data => _data;

  ValidationResult get validation => _validation;
  List<ValidationError> get errors => _validation.errors;
  bool get isValid => _validation.valid;

  /// Errors bound to a data path, for field-level display.
  ///
  /// The path is expressed as segments; [ValidationError.instancePath] is a
  /// JSON Pointer, so `['assessment', 'spo2']` matches `/assessment/spo2`.
  Iterable<ValidationError> errorsAtPath(List<String> segments) {
    final pointer = segments.isEmpty ? '' : '/${segments.join('/')}';
    return _validation.errorsAt(pointer);
  }

  /// Read the value at a data path.
  Object? valueAt(List<String> segments) => getValueAtPath(_data, segments);

  /// Write a value, copy-on-write along the changed path only.
  ///
  /// Untouched subtrees keep their identity, which is what makes selective
  /// rebuilds possible later without changing any call site.
  void updateAt(List<String> segments, Object? value) {
    if (readOnly) return;
    _data = setValueAtPath(_data, segments, value);
    _afterWrite();
  }

  /// Remove the value at a data path.
  ///
  /// Distinct from writing null, and the difference is visible in the submitted
  /// JSON: unchecking a checklist cell deletes its key rather than storing
  /// `false`. See ARCHITECTURE.md section 4.
  void removeAt(List<String> segments) {
    if (readOnly) return;
    _data = deleteValueAtPath(_data, segments);
    _afterWrite();
  }

  /// Replace the whole data object, e.g. when a draft is loaded.
  void replaceData(Map<String, dynamic> data) {
    _data = Map<String, dynamic>.from(data);
    _afterWrite();
  }

  void _afterWrite() {
    _revalidate();
    notifyListeners();
    onChange?.call(_data);
  }

  void _revalidate() {
    _validation = validator.validate(definition.dataSchema, _data);
  }
}

/// Makes a [FormStore] available to the widgets beneath it, rebuilding them
/// when it notifies.
class FormScope extends InheritedNotifier<FormStore> {
  const FormScope(
      {required FormStore super.notifier, required super.child, super.key});

  static FormStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FormScope>();
    assert(scope?.notifier != null, 'No FormScope found in the widget tree.');
    return scope!.notifier!;
  }

  /// Read the store without subscribing to its changes.
  ///
  /// For callbacks that write but do not display, so a tap handler does not
  /// force its own rebuild.
  static FormStore read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<FormScope>();
    assert(scope?.notifier != null, 'No FormScope found in the widget tree.');
    return scope!.notifier!;
  }
}
