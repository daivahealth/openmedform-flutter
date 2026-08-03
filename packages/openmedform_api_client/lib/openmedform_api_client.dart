/// Typed client for the OpenMedForm API.
///
/// Kept separate from the renderer so the renderer performs no I/O and stays
/// usable inside a host (an EMR, say) that fetches forms its own way.
///
/// Built in M6 (#7); see ARCHITECTURE.md section 11 for the endpoint contract
/// and the constraints that are bugs if missed.
library;

// Exports are added in M6.
