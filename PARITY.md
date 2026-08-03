# Parity ledger

Control-by-control status against the React and Angular renderers.

[ADR-003](https://github.com/daivahealth/openmedform/blob/main/docs/ADR/003-json-forms-platform.md)
requires every renderer to implement every clinical control and to derive every value identically. A
control that exists in only one framework, or computes a value differently in each, means the same
form reads differently in the EMR than in the web app. This file records where that stands.

**Value derivation is the part that matters.** Visual differences between a web checkbox and a
Material one are expected and harmless; a differently-shaped submission payload is not. The
"payload" column below is the one to read.

Status: ✅ done · 🚧 in progress · ⬜ not started

---

## Clinical controls (`options.omf.control`, rank 20)

| `omf.control` | Status | Payload | Notes |
|---|---|---|---|
| `textarea` | ✅ | `string` | `omf.screen.rows` → `minLines`, default 3. |
| `radio` | ✅ | `string` (the enum code) | Exactly two options defaults to label-left / options-right, the paper YES/NO row. Option text is part of the tap target, matching the web's `<label>`. |
| `signatureDate` | ✅ | `{printedName?, date?}` | Typed, not drawn — as in every shipped renderer. An emptied field is removed rather than stored blank. |
| `riskStratification` | ✅ | display only | Echoes the stored value, else "Calculated on submission". |
| `clinicalReferenceTable` | ✅ | display only | Static `omf.headers` + `omf.rows`. |
| `colorCodedGrid` | ✅ | display only | Row background from `omf.rows[].color`. |
| `vitalSignsChart` | ✅ | display only | Read-only table of the bound array against `omf.columns`. |
| `scoringMatrix` | ✅ | `{field: bool}` | Live subtotal computed locally, matching the web. The server recalculates authoritatively. |
| `checklistMatrix` | ✅ | `{rowKey: {colKey: true}}` | **Unchecking deletes the key**; an emptied row map is removed. Storing `false` would diverge from the web payload. |
| `scoreSummary` | ✅ | display only | Reads the whole form via form-core's `collectScoreItems` / `computeScore`. |
| `recordTable` | ✅ | array of objects | Both orientations. Editable cells dispatch the real control against the *item* schema; derived columns stay text. Detail from `options.detail`, else generated. Add seeds via `createRecordDefault` and auto-opens. |

## Layouts

| Element | Status | Notes |
|---|---|---|
| `VerticalLayout` | ✅ | |
| `HorizontalLayout` | ✅ | `omf.screen.colSpan` out of 12; stacks below 640 px via `LayoutBuilder`, so an embedded form reacts to its own width rather than the screen's. |
| `Group` | ✅ | Accent colour, icon de-duplication, point legend, live Σ subtotal, `variant: 'subsection'`. |
| `Label` | ✅ | Source line breaks preserved. |
| `OmfTableLayout` / `OmfTableRow` | ✅ | Both modes: header-and-cells with labels suppressed, or `row label \| contents`. |
| `OmfTabsLayout` | ✅ | Only the active page is mounted, as on the web. |
| `Categorization` / `Category` | ✅ | **Deliberate difference — see below.** |

## Standard controls

| Schema | Status | Payload | Notes |
|---|---|---|---|
| `string` | ✅ | `string` | Cleared field removes the value rather than storing `""`. |
| `integer` / `number` | ✅ | `int` / `double` | Never a `String`. A half-typed value such as `-` leaves the last good value in place. |
| `boolean` | ✅ | `bool` | Optional point badge. |
| `enum` | ✅ | the raw code | Rendered as a dropdown unless `omf.control: radio`. |
| `string` + `format: date` | ✅ | `yyyy-MM-dd` | Platform date picker. |

---

## Deliberate differences

**`Categorization` / `Category`.** Neither shipped renderer implements these: React falls through to
JSON Forms' vanilla tabbed renderer, and Angular renders *nothing*. Flutter renders tabs, which
matches what a clinician actually sees on the web. Matching Angular would mean deliberately dropping
content.

**Enum options display raw codes.** The translations contract and form-core's translator both exist,
but no shipped renderer uses them — labels come from the UI schema and the data schema's titles, and
enum options render as stable codes. Flutter matches that by default. The translator is ported and
flag-gated so switching it on later is one flag, but doing so is a platform-wide decision, not a
renderer-local one.

**Humanised labels differ by call site.** For a property with no `title`, the platform humanises keys
three different ways. Each is ported at its own call site rather than unified — see
[CONFORMANCE.md](CONFORMANCE.md#known-divergences).

## Not implemented, deliberately

| Item | Why |
|---|---|
| `omf.control: 'pageColumns'` | Appears once in the reference fixture; no renderer matches it. Dead vocabulary. |
| `OmfPageLayout`, `OmfClinicalSection`, `OmfGridLayout`, `OmfPatientHeader`, `OmfCheckboxGroup`, `OmfSignatureBlock`, `OmfCommentsBlock`, `OmfPrintHeader`, `OmfPrintFooter`, `OmfStaticText` | Declared in the type vocabulary, implemented in no renderer, emitted by no generator. Building them here would create parity in the wrong direction. |

Both render as a visible `UnknownElementWidget`, which is the correct outcome: it surfaces the gap
rather than hiding it.

## What still proves parity

This ledger is a claim; the tests are the evidence.

- The **conformance suite** (134 cases) pins every value-derivation rule against the real form-core
  implementation.
- **Widget tests** assert the payload each control writes, not only that it draws.
- The **parity trace** replays a scripted sequence of clinician interactions and records the payload
  after every step.
- **Live tests** render real published forms fetched from a running API.

### The parity trace

`packages/openmedform_flutter_renderer/test/parity_trace_test.dart` scripts thirteen interactions —
including the ones most likely to diverge: a cleared field, an unchecked boolean, an unchecked
matrix cell — and records the payload after each. Step by step matters: two renderers can disagree in
the middle, one writing `false` where the other deletes a key, and still converge on the same final
object.

The recorded trace is checked in at `test/parity/parity_trace.flutter.json` and is **the reference
the React renderer must reproduce**.

**It has already earned its place.** On its first run it caught a real divergence: clearing a text
field wrote `null` in Flutter, where React sets `undefined` — which disappears from the submitted
JSON entirely. Those are not equivalent. JSON Schema `required` checks key *presence*, so a null
would satisfy `required` and then fail on type, while an absent key fails `required` outright: two
different server verdicts for the same clinician action. Cleared fields are now removed.

### What is not yet proven

**The React half of the trace is not generated.** `tool/parity_export.tsx` is written and ready, but
it cannot run: in the monorepo's React test environment, `fireEvent` does not reach the renderer's
handlers — the DOM value changes and `onChange` never fires, not even on mount. The repository's own
React tests only assert on rendered output and never drive interactions, so there is no working
precedent to copy, and fixing that belongs upstream rather than here.

Until it runs, `parity_trace_test.dart` records the Flutter side and reports the comparison as
skipped with that reason attached, rather than passing silently. Unblocking it needs one of:

1. React interaction testing fixed in the monorepo (then the harness runs as documented), or
2. both demos driven through a browser, which is heavier but tests the real apps.

This is the one M7 exit criterion not met, and it is recorded as such on
[#8](https://github.com/daivahealth/openmedform-flutter/issues/8).
