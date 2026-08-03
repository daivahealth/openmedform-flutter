/// Pure Dart port of `@openmedform/form-core`.
///
/// This library must never import `package:flutter` — it is consumed by the
/// renderer, but is also usable from plain Dart (CLI tooling, server-side
/// validation, tests). CI enforces this; see `melos run check:purity`.
///
/// Modules land across M1 (#2) and M2 (#3); see ARCHITECTURE.md section 3 for
/// the port table mapping each TypeScript source to its Dart file.
library;

// Exports are added as each module is ported.
