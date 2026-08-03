# openmedform_flutter_renderer

Renders [OpenMedForm](https://github.com/daivahealth/openmedform) clinical form schemas as Flutter
widgets.

Transport-free by design: hand it a form definition, get form data back. Fetching and submitting
belong to the host app, or to `openmedform_api_client`.

```dart
OmfFormRenderer(
  definition: definition,
  initialData: submission.data,
  onChange: (data) => autosave(data),
)
```

## What it renders

Every clinical control the React and Angular renderers implement, because
[ADR-003](https://github.com/daivahealth/openmedform/blob/main/docs/ADR/003-json-forms-platform.md)
treats a partially-implemented renderer as a clinical-safety problem: `textarea`, `radio`,
`signatureDate`, `riskStratification`, `clinicalReferenceTable`, `colorCodedGrid`,
`vitalSignsChart`, `scoringMatrix`, `checklistMatrix`, `scoreSummary` and `recordTable`, plus the
`OmfTableLayout` and `OmfTabsLayout` layouts and the `Group` extras (accent colour, icon, point
legend, live subtotal, subsection variant).

Status per control is in [PARITY.md](../../docs/PARITY.md).

## Things worth knowing

**Values, not just pixels.** What ADR-003 constrains is the submitted payload. A cleared field is
*removed* rather than stored as `""` or `null`; unchecking a `checklistMatrix` cell deletes its key
rather than writing `false`; numeric controls emit `int`/`double`, never `String`. These are not
stylistic choices — they change what the server validates.

**Unknown elements are loud.** An element no control claims renders a visible placeholder naming its
type and scope. A silently dropped clinical field looks like a form that never asked the question.

**Local validation is advisory.** `POST /api/submissions/:id/complete` re-validates server-side and
recomputes every score; that verdict is the one that counts. This renderer validates only to help a
clinician fix problems sooner.

**Read-only means read-only.** The store itself refuses writes, not just the widgets — replaying a
signed submission cannot alter it.

## Theming

`OmfTheme` is a `ThemeExtension`. Install it in your `ThemeData` and the renderer will use it; pass
`theme:` to override for one form. `OmfTheme.defaults()` matches the web renderers pixel for pixel,
including the twelve `--omf-*` variables the upstream token package never defines but the web
renderers rely on.

## Extending

Controls resolve through a `ControlRegistry` using the same tester ranks as `form-core`
(`byOmfControl` 20, `byOmfLayout` 15, `bySchemaType` 8, `byType` 5). Register your own to add or
override one:

```dart
final registry = createDefaultRegistry()
  ..register(byOmfControl('myControl'), (context) => MyControl(context: context));

OmfFormRenderer(definition: definition, registry: registry);
```

## Testing

```bash
flutter test                     # widget tests
flutter test --tags golden       # pixel goldens (macOS; see the note below)
```

Goldens are excluded from CI: they rasterise differently on macOS and Linux, and a suite that fails
on the runner's platform rather than on a real regression teaches everyone to ignore it. Fonts are
vendored under `test/fonts` so the images are reproducible.

## Licence

Apache-2.0, matching the openmedform repository.
