/// Flutter renderer for OpenMedForm clinical form schemas.
///
/// The renderer is transport-free: it is handed a form definition and emits
/// form data. Fetching and submitting belong to the host app, or to
/// `openmedform_api_client`.
///
/// The store, dispatcher and theme land in M3 (#4); controls follow in M4 (#5)
/// and M5 (#6). See ARCHITECTURE.md sections 5, 6 and 9.
library;

// Exports are added as each layer is built.
