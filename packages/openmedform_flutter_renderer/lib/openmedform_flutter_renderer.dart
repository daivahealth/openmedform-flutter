/// Flutter renderer for OpenMedForm clinical form schemas.
///
/// The renderer is transport-free: it is handed a form definition and emits
/// form data. Fetching and submitting belong to the host app, or to
/// `openmedform_api_client`.
///
/// Start at [OmfFormRenderer]. See ARCHITECTURE.md sections 5, 6 and 9 for the
/// dispatch model, the state model, and the control inventory.
library;

export 'src/controls/standard_controls.dart';
export 'src/dispatch/default_registry.dart';
export 'src/dispatch/dispatcher.dart';
export 'src/dispatch/render_context.dart';
export 'src/layouts/layouts.dart';
export 'src/omf_form.dart';
export 'src/store/form_store.dart';
export 'src/theme/omf_theme.dart';
export 'src/widgets/field_frame.dart';
