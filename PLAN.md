# Delivery Plan — OpenMedForm Flutter Renderer

How the renderer described in [ARCHITECTURE.md](ARCHITECTURE.md) gets built. Each phase below is
tracked as a [GitHub issue](https://github.com/daivahealth/openmedform-flutter/issues).

---

## Scope

**v1 delivers full control parity.** Every clinical control and custom layout that exists in the
React and Angular renderers exists here, because
[ADR-003](https://github.com/daivahealth/openmedform/blob/main/docs/ADR/003-json-forms-platform.md)
treats a partially-implemented renderer as a clinical-safety problem rather than an incomplete
feature. A form that renders in the web app must render here.

Delivered as three Dart packages plus a demo app (see
[ARCHITECTURE.md § 2](ARCHITECTURE.md#2-repository-layout)):

- `openmedform_form_core` — pure Dart port of `@openmedform/form-core`
- `openmedform_flutter_renderer` — the renderer, transport-free
- `openmedform_api_client` — typed API client
- `apps/demo` — login → fill → autosave → complete → replay

**Non-goals** are listed in [ARCHITECTURE.md § 12](ARCHITECTURE.md#12-deferred--non-goals): offline
drafts, drawn signatures, SSO, print/PDF, the unimplemented `Omf*` vocabulary, and i18n display.

## Sequencing principle

Two things could force a rewrite if discovered late: **JSON Schema validation fidelity in Dart** and
**`recordTable`**. Validation is scheduled second, immediately after the core port makes it testable,
because a negative answer changes the architecture. `recordTable` is scheduled last, because it
composes almost everything else and is expensive but not architecturally risky.

Everything is gated on the conformance suite, which is why building it is phase zero rather than a
testing afterthought.

---

## M0 — Repo scaffold and conformance fixtures

Melos workspace, three package skeletons, CI, and the parity harness that every later phase depends
on.

- `melos.yaml`, package skeletons with `pubspec.yaml`, analysis options (including a CI check that
  `openmedform_form_core` imports no Flutter).
- GitHub Actions: `melos run analyze`, `melos run test`.
- Hand-extract the first conformance fixtures from the assertions in
  `openmedform/packages/form-core/src/**/*.test.ts` into `test/conformance/`.
- Copy the `rrtSbarReference` fixture and its two sample datasets in as JSON.
- `CONFORMANCE.md`: the pinned `form-core` SHA, regeneration procedure, comparison rules.

**Exit:** `melos bootstrap` and CI green on empty packages; fixtures checked in with their source SHA
recorded.

## M1 — Core port

Modules 1–9 from [ARCHITECTURE.md § 3](ARCHITECTURE.md#3-the-core-port) — everything except
validation and the rules that depend on it.

- `schema/types`, `schema/pointer`, `binding/data_path`, `schema/labels`
- `registry/control_registry`, `i18n/translate`
- `scoring/score`, `record_table/summary`, `serialization/response`
- Copy-on-write `updateAtPath` with its remove sentinel
  ([§ 4](ARCHITECTURE.md#4-data-conventions))

Watch the behaviours called out in § 3: `isPresent()`'s exact accepted values, the every-other-segment
scope mapping, and lodash `startCase` label derivation.

**Exit:** the `pointer`, `data_path`, `labels`, `scoring`, `record_table`, and `serialization`
conformance suites pass against both rrt-sbar sample datasets.

## M2 — Validation and rules · highest risk

Resolve the one open architectural question, then build rule evaluation on the answer.

- Evaluate `json_schema` against the `validation` conformance suite; confirm its 2020-12 coverage and
  maintenance status on pub.dev first.
- Implement the `OmfValidator` abstraction and its wrapper, mapping errors to
  `{instancePath, keyword, message, params}`.
- Enable only the formats actually used: `date`, `date-time`, `time`, `email`.
- Port `rules/evaluate_rule` on top, including the no-schema "value is present" case.
- Write the go/no-go memo into `CONFORMANCE.md`, listing every gap as either a shim or a documented
  server-only keyword.

**Exit:** rrt-sbar validates identically to Ajv — same `valid`, same `(instancePath, keyword)`
pairs — on both sample datasets; the `rules` suite passes; the decision and its gaps are recorded.

## M3 — Render skeleton

First pixels. The dispatch, state, and theme machinery, plus standard elements only.

- `FormStore` + `InheritedNotifier` scope; read-only flag.
- `DispatchRenderer`, `RenderContext`, default registry at form-core ranks, `UnknownElementWidget`.
- `OmfTheme` `ThemeExtension` — token values *and* the 12 undocumented fallbacks *and* the
  point-badge palette ([§ 8](ARCHITECTURE.md#8-theme)).
- `FieldFrame`; Vertical/Horizontal/Group/Label; text, number/integer, boolean, enum, date controls.
- Rule wiring: `HIDE` → collapse, `DISABLE` → disable.

**Exit:** rrt-sbar renders end-to-end with clinical controls appearing as `UnknownElementWidget`
placeholders; first golden test committed.

## M4 — Clinical controls

Everything in [§ 9](ARCHITECTURE.md#9-control-inventory) except `recordTable`, easiest first so the
patterns settle before the harder ones.

1. `textarea`, `radio`, `signatureDate`, `riskStratification`
2. Display-only tables: `vitalSignsChart`, `colorCodedGrid`, `clinicalReferenceTable`
3. `checklistMatrix` (key-deletion semantics), `scoringMatrix` (live subtotal), `scoreSummary`
   (whole-form read)
4. `OmfTableLayout` / `OmfTableRow`, `OmfTabsLayout`, and the Group extras: accent colour, icon
   de-duplication, point legend, live Σ subtotal, subsection variant

**Exit:** every listed control has a widget test and a golden; `PARITY.md` rows filled in, including
the deliberate `Categorization` difference from Angular.

## M5 — recordTable

The composite control. See [§ 9](ARCHITECTURE.md#recordtable) for the full behaviour list.

- Tester including the array-of-objects safety net.
- Both orientations; pinned actions column; synthesized editable cells through the dispatcher.
- `options.detail` and the `Generate.uiSchema` fallback; `createRecordDefault` seeding with
  auto-open; `removeConfirm` dialog; count templating.

Transliterate `react-form-renderer`'s `record-table.test.tsx` — 420 lines of ready-made cases.

**Exit:** those cases pass in Dart; full control parity reached; `PARITY.md` complete.

## M6 — API client and demo app

- `openmedform_api_client`: auth, forms (with the `toJsonFormsDefinition` fallbacks), submissions
  with exact DTOs ([§ 11](ARCHITECTURE.md#11-api-integration)).
- Demo screens: login → slug entry → fill with 3-second debounced autosave → complete → replay.
- Flush pending autosave before `/complete`; map 400 `instancePath` errors onto fields; show the
  server-computed scores on success.

**Exit:** a live run against a local API — fill, complete, and the server's scores match what
`scoreSummary` displayed locally; an invalid submission's 400 highlights the right fields.

## M7 — Hardening and release prep

- Goldens at both breakpoints (below and above 640 px).
- Read-only mode verified across every control.
- Error-path UX: 401 → re-login, 400 → field mapping, network failure during autosave.
- Package READMEs, dartdoc on public API, publishing metadata.

**Exit:** full golden suite green; the ADR-003 acceptance test passes.

---

## Verification

**Conformance suite** — the parity gate. `melos run test` runs it; CI fails on any drift.

**Widget tests** — interaction to data assertions: tapping a checkbox mutates the expected path;
unchecking a `checklistMatrix` cell *deletes* the key rather than writing `false`; `recordTable` add
seeds defaults and opens the detail panel.

**Golden tests** — rrt-sbar in full plus each control in isolation, at both breakpoints, with a
bundled font for determinism. Prefer the built-in `matchesGoldenFile`; evaluate `alchemist` at M7 if
more structure is wanted (`golden_toolkit` is discontinued).

**End-to-end** — bring the API up from the monorepo with `docker compose up`, seed and publish the
rrt-sbar form, then run the demo: login → fill → confirm the 3-second autosave debounce in the API
logs → complete → compare server scores against the local `scoreSummary` → open the read-only replay.

**ADR-003 acceptance test** — the one that actually proves parity: fill the same form with the same
input sequence in `openmedform/apps/react-demo` and in the Flutter demo, then diff the two persisted
`data` payloads. They must be identical JSON. A difference here is a release blocker regardless of
how good the screenshots look.

---

## Follow-ups in the openmedform monorepo

These belong in a separate PR against
[daivahealth/openmedform](https://github.com/daivahealth/openmedform), not in this repository.

1. **A new ADR** recording that a third renderer exists, that it inherits the ADR-003 parity
   obligation, and that the conformance suite is the enforcement mechanism.
2. **A conformance-export script** in `form-core` that emits the JSON fixtures from the existing
   tests and Ajv, so parity fixtures regenerate instead of being hand-maintained.
3. **`form-design-tokens` gaps**: emit a `tokens.json` artifact so non-JS renderers stop hand-copying
   values, promote the 12 undocumented fallback variables and the point-badge palette into the token
   set, and reconcile the two variables used with conflicting fallbacks
   (`--omf-color-section-bg`: `#f7f8fa` vs `#f0eaf4`; `--omf-section-gap`: `20px` vs `16px`).
4. **Three humanization rules for a title-less property key** — `controlLabel` in the print engine,
   `humanizeKey` in `record-table/summary.ts`, and lodash `startCase` inside JSON Forms all differ
   (see [CONFORMANCE.md](CONFORMANCE.md#known-divergences)). Whether that is intended is an upstream
   call; the port preserves all three rather than picking one.
4. **Documentation pointers** to this repository from the README and
   `docs/integration/THIRD-PARTY-GUIDE.md`.

### Known-stale monorepo docs

Found while researching this design. Flagged, not fixed — they are outside this effort's scope, but
anyone building against them will be misled:

- `docs/api/README.md` documents endpoints that ADR-004 deleted (`POST /api/forms/from-file`,
  `/from-pdf`, `PUT /api/forms/:id/schema`, `POST /api/forms/:id/ai/refine`, and the
  `POST /api/ai/generate*` block). None exist in the current controllers.
- `docs/features/EMR-INTEGRATION.md` is entirely pre-ADR-004: it documents the deleted
  `@openmedform/renderer` package and a `FormRenderer` prop signature that no longer exists.

---

## Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| **No Dart validator matches Ajv's 2020-12 fidelity** | High — rule evaluation depends on it; a poor validator means wrong conditional visibility, not just weak error messages | M2 is scheduled early and gated on a real conformance run. The `OmfValidator` abstraction keeps the package swappable. Server stays authoritative, so the worst case degrades UI quality rather than data integrity. |
| **`recordTable` complexity** | Medium–high — the single largest control, with no Flutter equivalent for sticky positioning | Scheduled last, when dispatch and path composition are proven. Fallback for row-height sync identified (`linked_scroll_controller`). 420 lines of existing test cases to transliterate. |
| **Hand-transliterated types drift from `form-schema-types`** | Medium — silent divergence as the platform evolves | Per-file source + SHA headers, a single pinned SHA in `CONFORMANCE.md`, and generated fixtures that fail loudly when upstream behaviour changes. |
| **Undocumented theme values** | Medium — visual divergence that looks like a styling nitpick but signals mis-ported semantics | All 12 fallbacks captured in `OmfTheme` up front; goldens at both breakpoints; upstream fix proposed as a follow-up. |
| **Parity regressions as `form-core` evolves** | Medium | The conformance suite is a CI gate, not a checklist. Bumping the pinned SHA is a deliberate PR. |
| **Flutter has no CSS table/sticky primitives** | Medium — affects `OmfTableLayout`, `recordTable`, and column widths | Approaches chosen per widget in [§ 9](ARCHITECTURE.md#9-control-inventory) rather than reaching for a general-purpose table package. |
