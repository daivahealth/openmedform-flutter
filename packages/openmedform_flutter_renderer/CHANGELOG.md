# Changelog

## 0.1.0

First release.

Renders OpenMedForm clinical form schemas as Flutter widgets. Transport-free: it takes a form
definition and emits form data.

- Every clinical control the React and Angular renderers implement — `textarea`, `radio`,
  `signatureDate`, `riskStratification`, `clinicalReferenceTable`, `colorCodedGrid`,
  `vitalSignsChart`, `scoringMatrix`, `checklistMatrix`, `scoreSummary` and `recordTable` — plus the
  `OmfTableLayout` and `OmfTabsLayout` layouts and the `Group` extras.
- Payload shapes match the web renderers exactly: a cleared field is removed rather than nulled, an
  unchecked matrix cell is deleted rather than set to `false`, and numeric controls emit numbers.
- Rules (`SHOW`/`HIDE`/`ENABLE`/`DISABLE`), live scoring with risk banding, read-only replay, and a
  `ThemeExtension` matching the platform's design tokens.
- Controls resolve through a registry at the platform's own tester ranks, so a host can add or
  override one.
- An element no control claims renders a visible placeholder rather than disappearing.

Local validation is advisory; the server re-validates and recomputes every score on completion.
