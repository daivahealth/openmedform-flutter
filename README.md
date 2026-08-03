# openmedform-flutter

A **Flutter renderer for [OpenMedForm](https://github.com/daivahealth/openmedform)** clinical form schemas.

OpenMedForm is an AI-powered clinical form builder. A published form is stored as a separated
`dataSchema` / `uiSchema` / `printSchema` (+ `translations`) triple, and renderers turn that triple
into a fillable form. The platform ships two renderers today — React and Angular — so the same form
definition can render inside the web app and inside an EMR. This repository adds a third, for
Flutter, so the same definitions can be filled on mobile.

## Status

**Planning. There is no code in this repository yet.**

The architecture and the phased delivery plan are written up first, and each phase is tracked as a
GitHub issue. Implementation starts at M0.

- [ARCHITECTURE.md](ARCHITECTURE.md) — technical design: the core port, dispatch model, state
  management, validation strategy, theme, and the full control inventory.
- [PLAN.md](PLAN.md) — scope, the eight delivery phases with exit criteria, verification strategy,
  and the risk register.
- [PARITY.md](PARITY.md) — control-by-control status against the React and Angular renderers.
- [CONFORMANCE.md](CONFORMANCE.md) — how cross-renderer parity is measured and enforced.
- [Issues](https://github.com/daivahealth/openmedform-flutter/issues) — one per phase, M0–M7.

## What this will contain

```text
openmedform-flutter/
├── packages/
│   ├── openmedform_form_core/        # pure Dart port of @openmedform/form-core (no Flutter imports)
│   ├── openmedform_flutter_renderer/ # the renderer: schema in → widgets out, data out
│   └── openmedform_api_client/       # typed client for the OpenMedForm API
└── apps/
    └── demo/                         # demo app: login → fill → autosave → submit → replay
```

The renderer package is transport-free: it takes a `FormDefinition` and gives back form data, exactly
like `@openmedform/react-form-renderer`. Fetching and submitting is the host app's job (or the
optional API client's).

## Scope of v1

**In:** full control parity with the React and Angular renderers — all eleven `omf.control` clinical
controls plus the custom layouts — server-side-authoritative validation and scoring, and a demo app
covering the whole fill-and-submit lifecycle.

**Out:** offline drafts, drawn signature capture, SSO login (browser-redirect based), and print/PDF
output. See [ARCHITECTURE.md § 12](ARCHITECTURE.md#12-deferred--non-goals).

## The parity obligation

[ADR-003](https://github.com/daivahealth/openmedform/blob/main/docs/ADR/003-json-forms-platform.md)
treats renderer divergence as a clinical-safety problem, not a cosmetic one: a control that exists in
only one framework, or derives a value differently in each, means the same form reads differently in
the EMR than in the web app. This repository inherits that obligation across every clinical control,
and enforces it with a shared JSON conformance suite rather than prose — see
[ARCHITECTURE.md § 10](ARCHITECTURE.md#10-the-conformance-suite).

## Related

- [daivahealth/openmedform](https://github.com/daivahealth/openmedform) — the platform: API, web app,
  schema contracts, and the React/Angular renderers.

## License

[Apache License 2.0](LICENSE), matching
[daivahealth/openmedform](https://github.com/daivahealth/openmedform). See [NOTICE](NOTICE) for
attributions.
