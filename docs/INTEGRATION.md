# Using the renderer in your own Flutter app

How to render OpenMedForm clinical forms inside a Flutter app you own — an EMR companion, a ward
round tool, anything that needs the same forms the OpenMedForm web app renders.

The renderer is transport-free: you hand it a form definition, it hands you back form data. Where the
definition comes from and where the data goes are yours to decide.

---

## 1. Add the dependency

The packages are not on pub.dev, so depend on the repository directly:

```yaml
dependencies:
  openmedform_flutter_renderer:
    git:
      url: https://github.com/daivahealth/openmedform-flutter.git
      path: packages/openmedform_flutter_renderer
      ref: main
```

Pin `ref` to a tag or commit for anything you ship — `main` moves.

`openmedform_form_core` comes along transitively. Add it explicitly only if you want its types
(`OmfFormDefinition`, `ValidationError`, the scoring helpers) in your own code:

```yaml
  openmedform_form_core:
    git:
      url: https://github.com/daivahealth/openmedform-flutter.git
      path: packages/openmedform_form_core
      ref: main
```

Add `openmedform_api_client` too if you want the ready-made API client rather than your own
networking — see [§ 6](#6-submitting).

### What it needs

| | |
|---|---|
| Dart SDK | ≥ 3.4 |
| Flutter | ≥ 3.22 |
| Platforms | all of them |

**No native code and no platform configuration.** The renderer is pure Flutter, and its
dependencies (`json_schema` for validation, `dio` in the optional API client) are pure Dart. Nothing
to add to `Info.plist`, `AndroidManifest.xml` or a Podfile — beyond whatever internet permission
your own networking already needs.

---

## 2. Get a form definition

An [`OmfFormDefinition`](../packages/openmedform_form_core/lib/src/schema/form_definition.dart) is
the `dataSchema` / `uiSchema` / `translations` triple the platform stores. Three common sources:

**From the OpenMedForm API**, using the bundled client:

```dart
final client = OmfApiClient(baseUrl: 'https://forms.example.org');
await client.auth.login(email: email, password: password);

final form = await client.forms.bySlug('rrt-sbar');
final definition = form.definition;
```

**From an export bundle** — `GET /api/forms/:id/export` returns everything in one self-contained
JSON document, which is what the platform documents for third-party renderers. Handy if you cache
forms or ship them with the app:

```dart
final definition = OmfFormDefinition.fromJson(
  jsonDecode(await rootBundle.loadString('assets/rrt-sbar.json'))
      as Map<String, dynamic>,
);
```

**From your own backend**, if it proxies or stores the schemas. `OmfFormDefinition.fromJson` accepts
any payload carrying `dataSchema` and `uiSchema`, and applies the same fallbacks the web app uses:
only `dataSchema` is guaranteed by the API, so a form with a null `uiSchema` renders as an empty form
rather than crashing.

---

## 3. Render it

```dart
OmfFormRenderer(
  definition: definition,
  initialData: draft.data,
  onChange: (data) => setState(() => _data = data),
)
```

`onChange` fires after every edit with the whole data object. That is the seam for autosave — debounce
it rather than writing on each keystroke.

`initialData` is what the form starts from. It is **not** re-read on rebuild: feeding your own state
back through it would fight the clinician's typing. To load a different draft, change the
`definition` or rebuild with a new `key`.

### Embedding in a screen that already scrolls

The renderer scrolls itself by default. Inside a host that scrolls, turn that off:

```dart
OmfFormRenderer(definition: definition, scrollable: false)
```

---

## 4. Get the data out

Either take it from `onChange`, or hold a key:

```dart
final formKey = GlobalKey<OmfFormRendererState>();

OmfFormRenderer(key: formKey, definition: definition);

// later
final data = formKey.currentState!.data;
```

### What the payload looks like

This is the part worth reading carefully. The shapes are not stylistic — they decide what the server
validates, and they match the React and Angular renderers exactly.

| Field | Written as |
|---|---|
| text | `String`; **cleared fields are removed**, not stored as `""` or `null` |
| number / integer | `double` / `int` — never a `String` |
| boolean | `bool` |
| enum | the raw code (`"VOICE"`), never the display text |
| date | `"yyyy-MM-dd"` |
| `signatureDate` | `{printedName, date}` |
| `checklistMatrix` | `{rowKey: {colKey: true}}` — **unchecking deletes the key** |
| `scoringMatrix` | `{field: bool}` |
| `recordTable` | a list of record objects |

The deletions matter more than they look. JSON Schema `required` checks whether a key is *present*,
so storing `null` where the web renderer removes the key produces a different verdict from the server
for the same clinician action.

---

## 5. Validation

The renderer validates as you type and shows errors under the fields, using the form's own JSON
Schema.

**That verdict is advisory.** The server re-validates on completion and recomputes every score;
client-computed scores are never accepted. Treat local validation as a way to catch problems sooner,
not as permission to submit.

---

## 6. Submitting

With the bundled client, the lifecycle and its sharp edges are handled for you:

```dart
final draft = await client.submissions.create(form.id);
final session = OmfSubmissionSession(client: client, submissionId: draft.id);

OmfFormRenderer(
  definition: form.definition,
  initialData: draft.data,
  onChange: session.onChanged,   // debounced autosave
);

// on submit — flushes the pending write first, then validates server-side
final completed = await session.complete();
```

Rolling your own is fine, but three constraints are easy to miss and each is a real bug:

- `PUT /api/submissions/:id` is a **full replace**, not a patch, and only valid while the submission
  is in progress.
- `POST /api/submissions/:id/complete` validates the **stored** data, so any pending autosave must
  land first. Racing your debounce timer submits whatever the server last saw.
- Request bodies must be exact. The API rejects unknown properties outright, so an extra key is a
  400 rather than something quietly ignored.

Handle the rejection so it reaches the fields:

```dart
try {
  await session.complete();
} on OmfValidationException catch (error) {
  for (final entry in error.byInstancePath.entries) {
    // entry.key is a JSON Pointer: "/assessment/spo2"
    highlight(entry.key, entry.value);
  }
}
```

---

## 7. Replaying a completed submission

Render read-only — and against the version the submission was **pinned** to, not the form's current
one. A form republished since would otherwise show the clinician's answers against different
questions:

```dart
final submission = await client.submissions.get(id);

OmfFormRenderer(
  definition: submission.formVersion!,
  initialData: submission.data,
  readOnly: true,
);
```

Read-only disables every control *and* the store beneath them, so a signed record cannot be altered
even by code that tries.

---

## 8. Theming

`OmfTheme` is a `ThemeExtension`. Install it once and every form picks it up:

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const <ThemeExtension<dynamic>>[
      OmfTheme(accent: Color(0xFF00695C), bodySize: 15),
    ],
  ),
);
```

Or override for a single form with `OmfFormRenderer(theme: ...)`.

`OmfTheme.defaults()` matches the web renderers pixel for pixel. Every value is overridable —
spacing, the type scale, borders, the section and header colours.

---

## 9. Adding your own control

Controls resolve through a registry using the same tester ranks as the platform's shared core
(`byOmfControl` 20, `byOmfLayout` 15, `bySchemaType` 8, `byType` 5). Register a higher-ranked entry
to add a control or replace a built-in one:

```dart
final registry = createDefaultRegistry()
  ..register(
    byOmfControl('bodyDiagram'),
    (context) => BodyDiagramControl(context: context),
  );

OmfFormRenderer(definition: definition, registry: registry);
```

Inside your control, `RenderContext` gives you the element, the resolved field schema, the current
value, any validation errors, and the store to write through:

```dart
class BodyDiagramControl extends StatelessWidget {
  const BodyDiagramControl({required this.context, super.key});
  final RenderContext context;

  @override
  Widget build(BuildContext buildContext) => FieldFrame.forContext(
        context,
        child: MyDiagram(
          value: context.value,
          enabled: context.enabled,
          onChanged: (next) => context.store.updateAt(context.path, next),
        ),
      );
}
```

**If you add a control, add it upstream too.** A control that exists only here means the same form
reads differently in your app than in the web app or the EMR — which
[ADR-003](https://github.com/daivahealth/openmedform/blob/main/docs/ADR/003-json-forms-platform.md)
treats as a clinical-safety problem rather than a cosmetic one.

---

## 10. When something looks wrong

**A red "Unsupported element" box.** No registered control matched that element. It names the type
and scope. This is deliberate — a clinical field that silently vanished would look like a form that
never asked the question. Either the form uses a control this renderer does not implement (check
[PARITY.md](PARITY.md)) or it carries vocabulary no renderer implements.

**Labels appear as humanised English on a non-English form.** The label chain is the element's
`label`, then the field schema's `title`, then the humanised property key. A form relying on `title`
for its language will fall through if that `title` is missing.

**The server rejects a field that looks filled in.** Check the payload rather than the screen. The
usual causes are a value stored as the wrong type, or a cleared field stored as `null` where the
schema expects the key to be absent.

**A form renders but overflows.** Report it with the form's UI schema. Real converted forms nest
layouts more deeply than any synthetic test — every layout bug found so far came from a real
published form, not a fixture.

---

## See also

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the renderer works inside
- [PARITY.md](PARITY.md) — control-by-control status against the web renderers
- [CONFORMANCE.md](CONFORMANCE.md) — how cross-renderer equivalence is measured
- [`apps/demo`](../apps/demo) — a working app covering the whole lifecycle
