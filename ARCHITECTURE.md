# Architecture — OpenMedForm Flutter Renderer

Technical design for the Flutter renderer. Companion to [PLAN.md](PLAN.md), which sequences the work.

Throughout, `openmedform/…` paths refer to files in
[daivahealth/openmedform](https://github.com/daivahealth/openmedform).

---

## 1. Relationship to openmedform

OpenMedForm separates a form into three schemas plus translations. That separation is what lets one
definition serve the web app, an EMR, and A4 print
([ADR-003](https://github.com/daivahealth/openmedform/blob/main/docs/ADR/003-json-forms-platform.md)):

```text
form-schema-types      types only, no runtime — the contracts
      │
form-core              framework-free engine: pointers, binding, rules, scoring, validation
      │
      ├── react-form-renderer     @jsonforms/react
      ├── angular-form-renderer   @jsonforms/angular
      ├── form-print-engine       UI+Print schema → A4 HTML/CSS
      └── openmedform_flutter_renderer   ← this repository
form-design-tokens     shared --omf-* visual constants, consumed by every renderer
```

### The inherited constraint

ADR-003 states the rule this repository is bound by:

> Both renderers must implement every clinical control. A control that exists in only one framework,
> or derives a value differently in each, would mean the same form reads differently in the EMR than
> in the web app — a clinical safety problem, not a cosmetic one.

A third renderer makes this "every renderer". Two consequences drive the design below:

1. **Value derivation must be identical, not merely similar.** Filling the same form with the same
   inputs must produce byte-identical submission JSON in React, Angular, and Flutter. This is
   enforced mechanically by the conformance suite (§10), not by review.
2. **A control is not "done" until it matches.** Partial implementations are worse than absent ones,
   because absent controls fail loudly (§5) while wrong ones fail silently.

### Sync model

This repository is not a monorepo package and cannot import TypeScript. The Dart core is a **hand
transliteration** of `form-core`, which means drift is possible. Mitigations:

- Every ported Dart file carries a header naming its TypeScript source and the `form-core` commit
  SHA it was ported from.
- The repository pins one `form-core` SHA in `CONFORMANCE.md`; bumping it is a deliberate PR that
  re-runs the conformance suite.
- The conformance fixtures are generated from the TypeScript side (§10), so a behavioural change in
  `form-core` surfaces as a Dart test failure rather than as silent divergence.

---

## 2. Repository layout

A [melos](https://pub.dev/packages/melos) workspace — chosen over a single package because the
core/renderer split mirrors `form-core` / `react-form-renderer`, and melos gives path-dependency
wiring plus one-command test runs across packages.

```text
openmedform-flutter/
├── melos.yaml
├── packages/
│   ├── openmedform_form_core/           # pure Dart. Zero Flutter imports — enforced in CI.
│   │   ├── lib/src/{schema,binding,rules,i18n,scoring,record_table,registry,serialization,validation,generate}/
│   │   └── test/conformance/            # JSON fixtures shared with the TS implementation
│   ├── openmedform_flutter_renderer/    # depends on form_core + flutter
│   │   ├── lib/src/{store,dispatch,layouts,controls,clinical,theme,widgets}/
│   │   └── test/                        # widget + golden tests
│   └── openmedform_api_client/          # auth, forms, submissions
└── apps/
    └── demo/                            # not published
```

**Why the API client is a separate package:** the renderer takes a `FormDefinition` and emits form
data — it never performs I/O. This mirrors `react-form-renderer`, which is handed a definition by
the host app, and keeps the renderer usable inside an EMR that fetches forms its own way.

Dart SDK ≥ 3.4, Flutter stable. CI runs `melos run analyze`, `melos run test`, and the golden suite.

---

## 3. The core port

`form-core` is ~1,271 lines of dependency-light TypeScript. Porting order follows its internal
dependency graph, so each module lands with its own conformance fixtures green.

| # | Dart file (`openmedform_form_core/lib/src/`) | TypeScript source (`openmedform/packages/`) | Notes |
|---|---|---|---|
| 1 | `schema/types.dart` | `form-schema-types/src/` | See "Typing the schemas" below. |
| 2 | `schema/pointer.dart` | `form-core/src/schema/pointer.ts` | Scope → schema/data segments; same-document `$ref`/`$defs` only. |
| 3 | `binding/data_path.dart` | `form-core/src/binding/data-path.ts` | Immutable get/set/delete by path or scope. |
| 4 | `i18n/translate.dart` | `form-core/src/i18n/translate.ts` | Ported, flag-gated (§6). |
| 5 | `registry/control_registry.dart` | `form-core/src/registry/control-registry.ts` | Direct transliteration incl. tester factories. |
| 6 | `scoring/score.dart` | `form-core/src/scoring/score.ts` | Clinical-safety critical. |
| 7 | `record_table/summary.dart` | `form-core/src/record-table/summary.ts` | Cell text, `{n}`/`{s}` templating, `EMPTY_CELL = '—'`. |
| 8 | `serialization/response.dart` | `form-core/src/serialization/response.ts` | Empty-response creation, pruning, submit serialization. |
| 9 | `schema/labels.dart` | `form-print-engine/src/render-html.ts` (`controlLabel`) | Label chain + `startCase`. |
| 10 | `validation/validator.dart` | `form-core/src/validation/validate-data.ts` | Adaptation, not transliteration — §7. |
| 11 | `rules/evaluate_rule.dart` | `form-core/src/rules/evaluate-rule.ts` | Depends on 10. |
| 12 | `generate/ui_schema.dart` | `@jsonforms/core` `Generate.uiSchema` + `createRecordDefault` | Minimal subset; needed only by `recordTable` detail fallback. |

### Typing the schemas

`dataSchema` stays a `Map<String, dynamic>` with typed extension accessors rather than a class
hierarchy. JSON Schema is open-ended (the TypeScript contract itself has an index-signature escape
hatch), and every validator wants the raw map. Modelling it as Dart classes would mean lossy
round-tripping for keywords we do not enumerate.

`uiSchema` **is** modelled as a sealed class hierarchy (`UiSchemaElement` → `Control`, `Group`,
`VerticalLayout`, …, with an `options.omf` bag), because the renderer switches on element type
exhaustively and Dart's exhaustiveness checking is worth having there.

### Rules a port must preserve

These are behaviours that look incidental and are not:

- **`isPresent()`** in scoring counts a value as present when it is `true`, `1`, `'1'`, `'yes'`, or
  any number greater than zero. Anything else — including `'YES'` — is absent.
- **Scope → data path** keeps every *other* segment starting at index 1:
  `#/properties/assessment/properties/spo2` → `['assessment', 'spo2']`.
- **Label derivation** is a three-step chain: the element's `label` when it is a string, else the
  resolved field schema's `title`, else the humanized last scope segment. The humanization is
  lodash's `startCase` (split camelCase/snake/kebab, capitalize each word), and it must match
  exactly — the reference fixture is a Greek form that relies on `title` to avoid English labels
  leaking in.
- **A rule condition with no `schema`** means "the value is present": not `undefined`, not `null`,
  not `''`. With a schema, it is a full JSON Schema validation of the scoped value.
- **Only leaf conditions exist.** JSON Forms' composite `AND`/`OR` conditions are not used by the
  platform and are not supported.

---

## 4. Data conventions

Form data is `Map<String, dynamic>` (decoded JSON) throughout.

**Copy-on-write updates.** `updateAtPath(data, segments, value)` rebuilds only the maps along the
changed path and shares every untouched subtree. This is cheap for forms of realistic size and gives
value-identity change detection for free, which is the upgrade path for selective rebuilds (§6).

**Deletion is a distinct operation, and it matters.** Several controls remove keys rather than
writing falsy values:

- `checklistMatrix` unchecking a cell **deletes** the `{rowKey: {colKey: true}}` entry; it never
  writes `false`. A row map left empty is itself removed.
- Pruning on submit removes empty values per `serialization/response.ts`.

Writing `false` where the web renderers delete a key produces different submission JSON for the same
clinical input — exactly the divergence ADR-003 forbids. `updateAtPath` therefore takes an explicit
remove sentinel rather than overloading `null`.

**Numbers.** JavaScript has only `double`; Dart distinguishes `int` from `double`, so a JSON
round-trip that yields `1` in Dart may be `1.0` in the fixtures. All conformance comparisons widen to
`num` before comparing. Controls bound to `number`/`integer` schemas must emit numeric values, never
strings — a text field that forwards its raw `String` silently changes the submitted type.

---

## 5. The rendering model

### Dispatch

`DispatchRenderer(element, path)` is the single recursive entry point, resolving each element through
the ported `ControlRegistry<Widget Function(RenderContext)>`:

```dart
class RenderContext {
  final UiSchemaElement element;
  final Map<String, dynamic>? fieldSchema;  // resolved from element.scope
  final List<String> path;                  // composed data path
  final FormStore store;
  final bool suppressLabel;                 // set by table layouts for their cells
  final bool enabled;
}
```

Testers score an element; the highest positive score wins; `NOT_APPLICABLE` (-1) means no match. The
ranks come straight from `form-core` and must not be re-invented:

| Tester | Rank | Matches |
|---|---|---|
| `byOmfControl(name)` | 20 | `options.omf.control == name` |
| `byOmfLayout(type)` | 15 | custom `Omf*` element type |
| `bySchemaType(type)` | 8 | `Control` whose resolved field schema has that type |
| `byType(type)` | 5 | standard element type (`Control`, `Group`, …) |

`form-core`'s registry is a framework-agnostic contract that neither shipped renderer actually uses
(both defer to JSON Forms' own `rankWith`). For a renderer with no JSON Forms runtime it is the
ready-made specification, which is why the Dart port uses it directly.

**Unknown elements fail loudly.** An element no tester matches renders as a visible
`UnknownElementWidget` showing its type and scope, rather than an empty box. A silently dropped
clinical field is the worst failure mode this renderer has; a visible placeholder is a bug report.

Hosts may `registry.register(tester, builder)` to add or override controls — the same extension story
as the React and Angular renderers.

**Path composition** uses `data_path.dart` exclusively. `recordTable` rows compose
`[...tablePath, '$index', ...cellSegments]`; there is one composition function and it is covered by
the `data_path` conformance cases.

### Reference implementation to follow

`openmedform/packages/form-print-engine/src/render-html.ts` (~175 lines) is the only framework-neutral
renderer in the platform: plain recursion over `UiSchemaElement` with a switch on `type`, no JSON
Forms runtime. That is precisely the shape of a Flutter widget builder, and it is the closest thing
to a specification for element semantics. Where it and the React renderer differ in a detail, the
React renderer wins — it is what clinicians actually use.

---

## 6. State management

**A plain `ChangeNotifier`, exposed through an `InheritedNotifier`. No Riverpod, no Bloc.**

```dart
class FormStore extends ChangeNotifier {
  final FormDefinition definition;
  final OmfValidator validator;
  final bool readOnly;

  Map<String, dynamic> get data;
  List<ValidationError> get errors;

  void updateAt(List<String> path, Object? value);  // COW → revalidate → notify → onChange
}
```

Rationale: the state this renderer owns is one small atom — form data plus derived errors — which is
exactly what the JSON Forms store it mirrors holds. A reusable package should not conscript its host
into a state-management framework, and `ChangeNotifier` + `ListenableBuilder` is idiomatic and
dependency-free. Riverpod would earn its place if there were async graph state to coordinate, but
fetching lives outside the renderer by design (§2).

**Rules are derived per build, not stored.** Each element evaluates `evaluateRule(rule, store.data)`
during `build`: `HIDE` → `SizedBox.shrink()`, `DISABLE` → `enabled: false` threaded down through
`RenderContext`. This matches how both shipped renderers behave and avoids a second source of truth
that can go stale. It also sidesteps a known Angular defect — under `OnPush`, a rule watching a
*sibling* control may not refresh until the sibling is interacted with. Flutter has no such
constraint and should simply be correct here.

**Rebuild granularity.** v1 rebuilds the form subtree on every change. Forms are modest and this is
what the React renderer effectively does. If profiling shows jank on the largest forms, the upgrade
path is per-scope selective listening keyed on the value identity that copy-on-write already
provides. Documented, deliberately not built.

**Read-only mode** is a store-level flag, not a per-widget concern, so submission replay renders the
identical tree with inputs disabled.

---

## 7. Validation strategy

### The constraint

`dataSchema` is JSON Schema **2020-12**, validated server-side by Ajv with `allErrors: true` and
`strict: false` plus `ajv-formats`. The reference fixture alone uses `$defs`/`$ref`, root-level
`allOf` with `if`/`then`, `enum`, `required`, `additionalProperties`, and `format: 'date'`.

Dart has no validator of Ajv's fidelity. But **delegating everything to the server is not possible**:
`evaluateRule` validates a scoped value against a condition schema on every rebuild, so some local
validator must exist regardless. Given that it exists, using it for field-level feedback too is
nearly free.

### The decision

**Use the [`json_schema`](https://pub.dev/packages/json_schema) package behind a swappable
abstraction, and keep the server authoritative.**

```dart
abstract class OmfValidator {
  ValidationResult validate(Map<String, dynamic> schema, Object? data);
}

class ValidationError {
  final String instancePath;  // '/assessment/spo2'
  final String keyword;       // 'required', 'maximum', 'type'
  final String message;
  final Map<String, dynamic> params;
}
```

The error shape is deliberately identical to both `form-core`'s `ValidationError` and the API's 400
payload, so error-rendering code does not care whether a message came from the local validator or the
server, and swapping the validator package changes one file.

Rationale for a maintained package over a hand-written subset: the keyword surface in production
schemas is small today, but schemas are author- and AI-generated, so the surface will grow. A subset
validator drifts silently; a real validator plus a conformance gate drifts loudly.

### Gap analysis is a test, not a guess

The `validation` conformance suite (§10) is generated from Ajv and run against the Dart validator in
CI. Every case compares `valid` plus the set of `(instancePath, keyword)` pairs — **not** message
text, which is validator-specific and will never match. A red case is resolved one of two ways: a
shim in the wrapper, or an entry in `CONFORMANCE.md` recording it as a server-only keyword. There is
no third option where a gap goes unrecorded.

**Kickoff task (M2):** confirm `json_schema`'s current 2020-12 coverage and maintenance status on
pub.dev, and run the suite before committing to it. The abstraction exists so that answer can be "no"
without re-architecting.

### Division of responsibility

Local validation is **advisory UI only**. `POST /api/submissions/:id/complete` re-validates with Ajv
and recalculates every score server-side; client-computed scores are never accepted, and the
submission DTOs have no field to send them in. The renderer's job is to help a clinician fix problems
before submitting, not to decide whether a submission is valid.

---

## 8. Theme

`OmfTheme` is a `ThemeExtension<OmfTheme>`, so hosts theme through standard `ThemeData.extensions`
and widgets read `Theme.of(context).extension<OmfTheme>()`. `OmfTheme.defaults()` reproduces the web
pixel values exactly.

Transliterated from `form-design-tokens/src/tokens.ts`:

| Group | Values |
|---|---|
| Grid | 12 columns, 12 px gap |
| Typography | body 14, label 13, section title 15, help 12; line height 1.4; label weight 600 |
| Spacing | field gap 12, section gap 20, section padding 16, control padding 8 |
| Controls | row min height 36, border width 1, border radius 4, textarea rows 3 |
| Color | border `#c8cdd4`, text `#1c2430`, label `#3a4552`, section bg `#f7f8fa`, invalid `#c0392b` |
| Breakpoints | sm 640, md 900 |

### The undocumented half

`cssVariables` defines 21 custom properties, but the renderers reference **12 more that the token
package never defines**, relying on inline `var(…, fallback)` defaults. Reproducing only the token
package would produce visibly wrong output, so `OmfTheme` carries all of them as first-class fields:

| Variable | Fallback in use |
|---|---|
| `--omf-color-accent` | `#4a2d5c` |
| `--omf-color-header-bg` | `#4a2d5c` |
| `--omf-color-header-fg` | `#fff` |
| `--omf-color-danger` | `#a3312a` |
| `--omf-color-muted` | `#6b7280` |
| `--omf-color-help` | `#6b7684` |
| `--omf-color-surface` | `#fff` |
| `--omf-control-gap` | `12px` |
| `--omf-subsection-indent` | `20px` |
| `--omf-table-label-width` | `16%` |
| `--omf-table-col-min` | `130px` |
| `--omf-font-mono` | `ui-monospace, SFMono-Regular, Menlo, monospace` |

Two variables are used with **inconsistent fallbacks** across call sites — `--omf-color-section-bg`
appears with both `#f7f8fa` (the token value) and `#f0eaf4` (a purple tint, in record-table headers),
and `--omf-section-gap` with both `20px` (the token value) and `16px`. The Dart theme takes the token
value as canonical and treats the odd ones out as local overrides on the specific widgets that use
them. Both are flagged upstream (§ PLAN, monorepo follow-ups).

**Point-badge palette**, hardcoded in both renderers and absent from the token package. Thresholds
are `>=`, evaluated top-down:

| Points | Foreground | Background |
|---|---|---|
| ≥ 5 | `#c0392b` | `#fdecea` |
| ≥ 3 | `#b8860b` | `#fbf3e0` |
| ≥ 2 | `#1e8e5a` | `#e8f6ee` |
| otherwise | `#2d6cdf` | `#e9f0fc` |

Fonts default to the platform system font, matching the web stack's `system-ui` intent. Golden tests
bundle an explicit font so they are deterministic across machines.

---

## 9. Control inventory

Every control below exists in both shipped renderers and is therefore mandatory here. Shared
chrome — label, required marker, help text, error text, point-badge slot — lives in
`widgets/field_frame.dart`, the port of `react-form-renderer`'s `field-frame.tsx`.

### Standard elements

| Element | Dart file | Notes | Risk |
|---|---|---|---|
| `VerticalLayout` | `layouts/vertical_layout.dart` | Column with field gap. | low |
| `HorizontalLayout` | `layouts/horizontal_layout.dart` | `omf.screen.colSpan` out of 12 → `Row` of `Flexible(flex:)`; stacks to one column below 640 px via `LayoutBuilder` (not `MediaQuery`, so it behaves when embedded). | med |
| `Group` | `layouts/group_layout.dart` | Bordered box + shaded header; `omf.accentColor`; `omf.icon` (de-duplicated when the label already starts with it); `omf.pointLegend` chips; live `Σ` subtotal; `omf.variant: 'subsection'` renders indented with no box. | med |
| `Label` | `layouts/label_element.dart` | Source line breaks are significant (`white-space: pre-line`); Flutter `Text` preserves `\n` natively. | low |
| `Control` | `controls/` | Dispatched by resolved schema type: text, number/integer (numeric values — never strings), boolean (checkbox + optional point badge), enum (dropdown, raw codes), `format: 'date'` (picker, `yyyy-MM-dd`). | low |
| `Categorization` / `Category` | `layouts/categorization.dart` | Neither shipped renderer implements these: React falls through to JSON Forms' vanilla tabs, Angular renders nothing. Flutter renders them as tabs, reusing the `OmfTabsLayout` widget. Recorded in `PARITY.md` as a deliberate difference from Angular. | low |

### Custom `Omf*` layouts

| Element | Dart file | Notes | Risk |
|---|---|---|---|
| `OmfTableLayout` + `OmfTableRow` | `layouts/omf_table_layout.dart` | Two modes. With `omf.columns`: a real header row, one cell per child, child labels suppressed via `RenderContext.suppressLabel`. Without: two-cell `row label | contents`. Flutter `Table` with intrinsic widths. | med |
| `OmfTabsLayout` | `layouts/omf_tabs_layout.dart` | Tab strip; **only the active page is built** (matches web, and keeps rule evaluation off hidden pages). Not `TabBarView`, which keeps children alive. | med |

### Clinical controls (`options.omf.control`, rank 20)

| `omf.control` | Dart file | Behaviour | Risk |
|---|---|---|---|
| `textarea` | `clinical/textarea.dart` | Multiline; `omf.screen.rows` → `minLines`, default 3. | low |
| `radio` | `clinical/radio.dart` | Enum radios. **Exactly two options defaults to label-left / options-right** — the paper YES/NO idiom. `screen.labelPosition` / `screen.inline` override. | low |
| `signatureDate` | `clinical/signature_date.dart` | Composite `{printedName, date}`: a text field and a date field. Typed, not drawn. | low |
| `riskStratification` | `clinical/risk_stratification.dart` | Echoes the bound value, or "Calculated on submission" when empty. | low |
| `clinicalReferenceTable` | `clinical/clinical_reference_table.dart` | Static `omf.headers` + `omf.rows`; display only. | low |
| `colorCodedGrid` | `clinical/color_coded_grid.dart` | Reference rows `{label, range, color}`; row background from `color`. Display only. | low |
| `vitalSignsChart` | `clinical/vital_signs_chart.dart` | Read-only table of the bound array against `omf.columns`. | low |
| `checklistMatrix` | `clinical/checklist_matrix.dart` | `omf.rows` × `omf.columns` checkbox grid; value `{rowKey: {colKey: true}}`. **Unchecking deletes the key** (§4). | med |
| `scoringMatrix` | `clinical/scoring_matrix.dart` | "Risk factor / Points / Present" table from `omf.domains[].items[{field,label,points}]`; value `{field: bool}`; live subtotal in the footer. Computed locally, not via `form-core`. | med |
| `scoreSummary` | `clinical/score_summary.dart` | Reads the **whole** form: `collectScoreItems(uiSchema)` + `computeScore(items, data, bands)` → grand total, per-section subtotals, risk band from `omf.bands`. The one control that needs root uischema and full data from the store. | med |
| `recordTable` | `clinical/record_table.dart` | See below. | **high** |

### `recordTable`

The hardest control, and the reason it is scheduled last — it composes the dispatcher, path
composition, the `Generate.uiSchema` port, and default seeding.

- **Tester**: `omfControlIs('recordTable')` **OR** any `Control` whose schema is an array of objects.
  That second arm is a deliberate safety net: an unconfigured object array becomes a record table
  with columns derived by `deriveRecordColumns` rather than falling through to a generic list widget.
  Both shipped renderers replicate it exactly.
- **Config** (`omf.recordTable`): `orientation` (`rows` | `columns`), `instanceLabel`, `addLabel`,
  `countLabel` (with `{n}` / `{s}` templating), `emptyLabel`, `removeConfirm`, and
  `columns[{label, path, countOf, pairWith, width, align}]`.
- **Editable cells**: a column with a `path` and no `countOf`/`pairWith` dispatches a *real*
  synthesized `Control` at the composed path, so the cell reuses the ordinary renderers and inherits
  their value derivation. Derived columns stay as text.
- **Detail panel**: one expandable row at a time, spanning full width. Its UI schema is
  `options.detail` when present, otherwise generated by the `Generate.uiSchema` port — typically an
  `OmfTabsLayout`.
- **Column orientation** transposes the whole table: field labels down the left, `instanceLabel N`
  headers across the top.
- **Pinned actions column**: the web uses `position: sticky; right: 0`, which Flutter has no
  equivalent for. Implementation is a `Row` of `[Expanded(horizontal-scrolling Table), fixed-width
  actions column]`, with row heights synchronised from the shared row-min-height. If variable row
  heights prove necessary, `linked_scroll_controller` is the fallback; no third-party sticky-table
  package in v1.
- **Add** seeds a record via `createRecordDefault(itemSchema)` (recursive: defaults, `{}` for
  objects, `[]` for arrays) and auto-opens its detail panel. `removeConfirm` is a dialog — the web
  uses `window.confirm`, which has no Flutter analogue.
- **Open is hidden** when every field is already a column (`hasDetail` false).

### Explicitly out of scope

| Item | Why |
|---|---|
| `omf.control: 'pageColumns'` | Appears once in the reference fixture; no tester matches it in any renderer. Dead vocabulary. |
| `OmfPageLayout`, `OmfClinicalSection`, `OmfGridLayout`, `OmfPatientHeader`, `OmfCheckboxGroup`, `OmfSignatureBlock`, `OmfCommentsBlock`, `OmfPrintHeader`, `OmfPrintFooter`, `OmfStaticText` | Declared in the type vocabulary, implemented in no renderer and emitted by no generator. Building them here would create parity in the wrong direction. |

Encountering any of these renders `UnknownElementWidget`, which is the correct outcome: it surfaces
the gap instead of hiding it.

---

## 10. The conformance suite

Parity is currently asserted by prose comments and per-framework tests. That is not enough for a
third implementation in a different language, so this repository introduces a machine-readable suite
and treats it as the parity gate.

Fixtures are plain JSON, one file per module:

```json
{
  "module": "scoring",
  "sourceCommit": "<form-core SHA>",
  "cases": [
    { "name": "counts 'yes' as present", "input": { "…": "…" }, "expected": { "…": "…" } }
  ]
}
```

Covering: `pointer`, `data_path`, `labels`, `rules`, `scoring`, `record_table`, `serialization`, and
`validation`.

- **Comparison rules**: numeric equality widens to `num` (§4); validation cases compare `valid` plus
  `(instancePath, keyword)` pairs only, never message text (§7).
- **Bootstrapping**: the first generation is hand-extracted from the assertions already present in
  `form-core/src/**/*.test.ts`. The format is the contract; its provenance can be manual initially.
- **Generation**: a follow-up PR in the monorepo adds a script that emits these files from the
  TypeScript implementation and Ajv, so they regenerate on every `form-core` change.
- **Golden form**: `form-core`'s `rrtSbarReference` fixture with its empty and completed sample data.
  It is a Greek RRT/SBAR form that exercises `$defs`/`$ref`, root `allOf`/`if`/`then`, `format:
  'date'`, a two-column layout, `recordTable`, and `scoreSummary` — nearly the whole surface in one
  document, and the same form both demo apps render.

`CONFORMANCE.md` records the pinned `form-core` SHA, the regeneration procedure, and every
known divergence with its justification.

---

## 11. API integration

Consumed by `openmedform_api_client` and the demo app; the renderer itself never performs I/O.

**Auth.** `POST /api/auth/login` with `{email, password}` returns `{accessToken, user}`. The token is
a bearer token and carries `tenantId` in its payload — there are **no tenant or facility headers**, and
no facility concept exists in the platform. SSO is a browser-redirect flow and is out of scope for v1.

**Fetching a form.** `GET /api/forms/slug/:slug` returns the form with its published
`currentVersion`. Only `dataSchema` is guaranteed — `uiSchema`, `printSchema`, `translations`, and
`scoringRules` are all nullable, and the client must apply the same fallbacks the web app does in
`apps/web/src/components/forms/jsonforms-renderer-wrapper.tsx` (`toJsonFormsDefinition`).
`GET /api/forms/:id/export` is the alternative: a self-contained bundle with schemas plus
base64-inlined assets, and the shape documented for third-party renderers.

**Submission lifecycle.**

```text
POST /api/forms/:formId/submissions   → creates a draft; server pins formVersionId
PUT  /api/submissions/:id  {data}     → autosave; FULL REPLACE, not a patch; IN_PROGRESS only
POST /api/submissions/:id/complete    → server-side Ajv validation + score recalculation
POST /api/submissions/:id/sign        → COMPLETED → SIGNED
```

Non-obvious constraints, each of which is a bug if missed:

- **The client never chooses a version.** `formVersionId` is pinned server-side at create time from
  the form's current published version.
- **`/complete` validates the *stored* data**, so any pending autosave must be flushed with a `PUT`
  before completing. The demo app's debouncer flushes explicitly rather than racing the timer.
- **DTOs must be exact.** The global validation pipe runs with `forbidNonWhitelisted`, so any unknown
  property is a 400. Create accepts only `{patientMrn?, encounterId?, patientContext?}`; update
  accepts only `{data}`.
- **Scores are never sent.** There is no DTO field for them; the server recalculates from
  `scoringRules` and writes `scores` and `riskLevel` itself.
- **Validation failure returns 400** with `{message, errors: [{instancePath, keyword, message,
  params}]}`. The demo maps `instancePath` back onto field scopes to highlight the offending
  controls.
- **Replay renders against `submission.formVersion`**, the pinned version — never the form's current
  version, which may have moved on.

---

## 12. Deferred / non-goals

| Not in v1 | Rationale |
|---|---|
| Offline drafts | Drafts live server-side, as in the web app. Local persistence adds sync, conflict, and PHI-at-rest concerns that deserve their own design. |
| Drawn signature capture | `signatureDate` is a typed name plus date in every shipped renderer. Adding drawing here would be renderer divergence. |
| SSO login | Browser-redirect based; needs a custom-scheme or webview flow that is independent of the renderer. |
| Print / PDF output | `form-print-engine` owns this, and the API already serves `GET /api/submissions/:id/pdf`. |
| The unimplemented `Omf*` vocabulary | See §9. |
| i18n display | The translations contract and `form-core`'s translator both exist, but **no shipped renderer uses them**: labels come from `uiSchema.label` → `dataSchema.title` → humanized key, and enum options render as raw stable codes. The translator is ported and flag-gated (`enableTranslations: false`) so Flutter matches web behaviour by default. Turning it on is a platform-wide decision, not a renderer-local one — stored values are language-independent codes either way. |
