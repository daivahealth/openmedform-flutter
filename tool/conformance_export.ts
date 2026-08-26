/**
 * Conformance fixture generator.
 *
 * Emits the JSON fixtures in `packages/openmedform_form_core/test/conformance/`
 * by calling the real `@openmedform/form-core` implementation, so the expected
 * values are authoritative rather than transcribed by hand.
 *
 * This file is TypeScript and does not run in this repository — it runs inside
 * the openmedform monorepo, which owns form-core and its Ajv dependency. It is
 * staged here so the fixtures stay reproducible until the upstream PR lands it
 * as a proper `form-core` script (see docs/PLAN.md → follow-ups).
 *
 * Usage, from a checkout of daivahealth/openmedform:
 *
 *   cp tool/conformance_export.ts \
 *      <openmedform>/packages/form-core/src/__conformance_export.test.ts
 *   cd <openmedform>/packages/form-core
 *   OMF_FIXTURE_OUT=<this-repo>/packages/openmedform_form_core/test/conformance \
 *   OMF_SOURCE_SHA=$(git -C <openmedform> rev-parse HEAD) \
 *     ./node_modules/.bin/vitest run src/__conformance_export.test.ts
 *   rm <openmedform>/packages/form-core/src/__conformance_export.test.ts
 *
 * It is shaped as a vitest test because form-core ships ESM TypeScript with no
 * build output, and vitest is the only runner already wired up for it.
 */
import { describe, it } from 'vitest';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

import {
  scopeToDataPath, scopeToDataPathSegments, scopeToSchemaSegments, resolveSchemaAtScope, derefSchema,
  resolveRef, decodePointerSegment,
  toPathSegments, getValueAtPath, setValueAtPath, deleteValueAtPath, getValueAtScope, setValueAtScope,
  evaluateCondition, evaluateRule, evaluateElementState, filterVisibleElements, hasElementRules,
  collectScoreItems, computeScore, stratify, scoreUiSchema, showsSectionSubtotal, elementBands,
  parseHexColor, accentTint, accentTintOpaque,
  elementOptionPoints, resolveEnumOptions, resolveMultiEnumOptions,
  readRecordPath, recordCellText, recordCountText, createRecordDefault, deriveRecordColumns,
  isColumnEditable, fieldsOutsideColumns, EMPTY_CELL,
  createEmptyResponse, pruneEmptyValues, serializeForSubmit,
  validateData,
  OMF_CONTROL_NAMES,
  resolveTranslation, hasLanguage,
  byOmfControl, byOmfLayout, byType, bySchemaType, NOT_APPLICABLE,
  rrtSbarReference, rrtSbarSampleEmpty, rrtSbarSampleCompleted,
} from './index';

const OUT = process.env.OMF_FIXTURE_OUT!;
const SHA = process.env.OMF_SOURCE_SHA!;
const UNDEF = '__undefined__';

/** JSON with explicit undefined markers — Dart distinguishes absent from null. */
function enc(v: unknown): unknown {
  if (v === undefined) return UNDEF;
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(enc);
  const out: Record<string, unknown> = {};
  for (const k of Object.keys(v as object)) out[k] = enc((v as Record<string, unknown>)[k]);
  return out;
}

type Case = { name: string; fn: string; args: unknown[] };
const files: Record<string, Case[]> = {};
function add(module: string, name: string, fn: string, ...args: unknown[]) {
  (files[module] ??= []).push({ name, fn, args });
}

const CALL: Record<string, (...a: never[]) => unknown> = {
  scopeToDataPath, scopeToDataPathSegments, scopeToSchemaSegments, resolveSchemaAtScope, derefSchema,
  resolveRef, decodePointerSegment,
  toPathSegments, getValueAtPath, setValueAtPath, deleteValueAtPath, getValueAtScope, setValueAtScope,
  evaluateCondition, evaluateRule, evaluateElementState, filterVisibleElements, hasElementRules,
  collectScoreItems, computeScore, stratify, scoreUiSchema, showsSectionSubtotal, elementBands,
  parseHexColor, accentTint, accentTintOpaque,
  elementOptionPoints, resolveEnumOptions, resolveMultiEnumOptions,
  readRecordPath, recordCellText, recordCountText, createRecordDefault, deriveRecordColumns,
  isColumnEditable, fieldsOutsideColumns,
  createEmptyResponse, pruneEmptyValues, serializeForSubmit,
  resolveTranslation, hasLanguage,
} as never;

const ds = rrtSbarReference.dataSchema;
const ui = rrtSbarReference.uiSchema;

// ---------------- pointer ----------------
// Escape decoding order is load-bearing: decoding ~0 first would turn ~01 into
// ~1 and then into '/', when it must decode to the literal '~1'.
add('pointer', 'decodes ~1 to a slash', 'decodePointerSegment', 'a~1b');
add('pointer', 'decodes ~0 to a tilde', 'decodePointerSegment', 'a~0b');
add('pointer', 'decodes ~01 to a literal ~1, not a slash', 'decodePointerSegment', 'a~01b');
add('pointer', 'simple scope to data path', 'scopeToDataPath', '#/properties/situation');
add('pointer', 'nested scope keeps every other segment', 'scopeToDataPath', '#/properties/assessment/properties/spo2');
add('pointer', 'nested scope to segments', 'scopeToDataPathSegments', '#/properties/assessment/properties/spo2');
add('pointer', 'schema segments retain properties keyword', 'scopeToSchemaSegments', '#/properties/assessment/properties/spo2');
add('pointer', 'root scope', 'scopeToDataPath', '#');
add('pointer', 'resolves schema at scope', 'resolveSchemaAtScope', ds, '#/properties/assessment/properties/spo2');
add('pointer', 'resolves an inline object scope', 'resolveSchemaAtScope', ds, '#/properties/callDetails');
// anticoagulantUse is the one $ref in the golden form: -> #/$defs/yesNo
add('pointer', 'resolves a scope through $ref into $defs', 'resolveSchemaAtScope', ds, '#/properties/anticoagulantUse');
add('pointer', 'unknown scope resolves to undefined', 'resolveSchemaAtScope', ds, '#/properties/nope/properties/missing');
add('pointer', 'resolveRef into $defs', 'resolveRef', ds, '#/$defs/yesNo');
add('pointer', 'resolveRef refuses an external ref', 'resolveRef', ds, 'https://example.com/schema.json#/$defs/yesNo');
// derefSchema takes the node first and the root second.
add('pointer', 'derefSchema follows a $ref node', 'derefSchema', { $ref: '#/$defs/yesNo' }, ds);
add('pointer', 'derefSchema passes through a plain node', 'derefSchema', { type: 'string' }, ds);
add('pointer', 'derefSchema on a dangling $ref', 'derefSchema', { $ref: '#/$defs/nope' }, ds);

// ---------------- data_path ----------------
add('data_path', 'dot path to segments', 'toPathSegments', 'assessment.spo2');
add('data_path', 'get nested value', 'getValueAtPath', { assessment: { spo2: 88 } }, 'assessment.spo2');
add('data_path', 'get missing intermediate is undefined', 'getValueAtPath', {}, 'assessment.spo2');
add('data_path', 'set creates intermediates immutably', 'setValueAtPath', {}, 'assessment.spo2', 92);
add('data_path', 'set overwrites leaving siblings', 'setValueAtPath', { assessment: { spo2: 88, hr: 120 } }, 'assessment.spo2', 95);
add('data_path', 'delete removes the key', 'deleteValueAtPath', { a: { b: 1, c: 2 } }, 'a.b');
add('data_path', 'delete of a missing key is a no-op', 'deleteValueAtPath', { a: { b: 1 } }, 'a.zzz');
add('data_path', 'get by scope', 'getValueAtScope', { assessment: { spo2: 88 } }, '#/properties/assessment/properties/spo2');
add('data_path', 'set by scope', 'setValueAtScope', {}, '#/properties/assessment/properties/spo2', 90);

// ---------------- rules ----------------
const spo2Low = { scope: '#/properties/assessment/properties/spo2', schema: { type: 'integer', maximum: 91 } };
add('rules', 'condition active when value matches schema', 'evaluateCondition', spo2Low, { assessment: { spo2: 88 } });
add('rules', 'condition inactive when value does not match', 'evaluateCondition', spo2Low, { assessment: { spo2: 98 } });
add('rules', 'missing schema is a presence check (present)', 'evaluateCondition', { scope: '#/properties/situation' }, { situation: 'text' });
add('rules', 'missing schema is a presence check (empty string)', 'evaluateCondition', { scope: '#/properties/situation' }, { situation: '' });
add('rules', 'missing schema is a presence check (absent)', 'evaluateCondition', { scope: '#/properties/situation' }, {});
add('rules', 'missing schema is a presence check (null)', 'evaluateCondition', { scope: '#/properties/situation' }, { situation: null });
add('rules', 'missing schema is a presence check (false is present)', 'evaluateCondition', { scope: '#/properties/situation' }, { situation: false });
add('rules', 'missing schema is a presence check (zero is present)', 'evaluateCondition', { scope: '#/properties/situation' }, { situation: 0 });
for (const effect of ['SHOW', 'HIDE', 'ENABLE', 'DISABLE']) {
  add('rules', `${effect} with condition active`, 'evaluateRule', { effect, condition: spo2Low }, { assessment: { spo2: 88 } });
  add('rules', `${effect} with condition inactive`, 'evaluateRule', { effect, condition: spo2Low }, { assessment: { spo2: 98 } });
}
add('rules', 'no rule defaults to visible and enabled', 'evaluateElementState', {}, {});
add('rules', 'element rule applied', 'evaluateElementState', { rule: { effect: 'SHOW', condition: spo2Low } }, { assessment: { spo2: 88 } });

// Root-scope conditions (form-core 1.7.1). A condition whose scope is '#'
// resolves to the WHOLE response, so its schema can combine several answers
// with ordinary JSON Schema — `properties` + `required` for AND, `anyOf` for
// OR. That is how a derived clinical outcome is expressed, and the conversion
// pipeline now emits it, so it is pinned here rather than left as behaviour
// that merely happens to work.
const present = { const: 'PRESENT' };
const absent = { const: 'ABSENT' };
// CAM-ICU: POSITIVE iff F1 AND F2 AND (F3 OR F4).
const camIcuPositive = {
  scope: '#',
  schema: {
    type: 'object',
    properties: { f1: present, f2: present },
    required: ['f1', 'f2'],
    anyOf: [
      { properties: { f3: present }, required: ['f3'] },
      { properties: { f4: present }, required: ['f4'] },
    ],
  },
};
add('rules', 'root scope resolves to the whole response', 'evaluateCondition', { scope: '#' }, { f1: 'PRESENT' });
add('rules', 'root-scope AND/OR: nothing answered', 'evaluateCondition', camIcuPositive, {});
add('rules', 'root-scope AND/OR: F1+F2, F3 unanswered', 'evaluateCondition', camIcuPositive, { f1: 'PRESENT', f2: 'PRESENT' });
add('rules', 'root-scope AND/OR: F1+F2+F3 present', 'evaluateCondition', camIcuPositive, { f1: 'PRESENT', f2: 'PRESENT', f3: 'PRESENT' });
add('rules', 'root-scope AND/OR: F3 absent but F4 present', 'evaluateCondition', camIcuPositive, { f1: 'PRESENT', f2: 'PRESENT', f3: 'ABSENT', f4: 'PRESENT' });
add('rules', 'root-scope AND/OR: F3 and F4 both absent', 'evaluateCondition', camIcuPositive, { f1: 'PRESENT', f2: 'PRESENT', f3: 'ABSENT', f4: 'ABSENT' });
add('rules', 'root-scope AND/OR: F1 absent', 'evaluateCondition', camIcuPositive, { f1: 'ABSENT', f2: 'PRESENT', f3: 'PRESENT' });

// filterVisibleElements — a container resolving its own children, used where
// the child IS the layout (a table row) and so never reaches a dispatch.
const showIfF1 = { effect: 'SHOW', condition: { scope: '#/properties/f1', schema: present } };
const disableIfF1 = { effect: 'DISABLE', condition: { scope: '#/properties/f1', schema: present } };
const rows = [
  { type: 'OmfTableRow', label: 'Feature 1' },
  { type: 'OmfTableRow', label: 'Feature 2', rule: showIfF1 },
  { type: 'OmfTableRow', label: 'Feature 3', rule: disableIfF1 },
];
add('rules', 'filters hidden children, keeping original indices', 'filterVisibleElements', rows, {});
add('rules', 'reveals a child once its rule holds', 'filterVisibleElements', rows, { f1: 'PRESENT' });
add('rules', 'ANDs parent enablement into every survivor', 'filterVisibleElements', rows, { f1: 'PRESENT' }, false);
add('rules', 'no elements yields no survivors', 'filterVisibleElements', undefined, {});
add('rules', 'hasElementRules true', 'hasElementRules', rows);
add('rules', 'hasElementRules false', 'hasElementRules', [{ type: 'OmfTableRow' }]);
add('rules', 'hasElementRules on nothing', 'hasElementRules', undefined);

// ---------------- scoring ----------------
const scoreUi = {
  schemaVersion: '1.0',
  layout: {
    type: 'VerticalLayout',
    elements: [
      { type: 'Group', label: 'AGE', elements: [
        { type: 'Control', scope: '#/properties/age/properties/age41to60', options: { omf: { points: 1 } } },
        { type: 'Control', scope: '#/properties/age/properties/age75plus', options: { omf: { points: 3 } } },
      ] },
      { type: 'Group', label: 'CARDIOVASCULAR', elements: [
        { type: 'Control', scope: '#/properties/cardiovascular/properties/acuteMI', options: { omf: { points: 1 } } },
      ] },
      { type: 'Control', scope: '#/properties/notes' },
    ],
  },
};
const bands = [{ maxScore: 1, label: 'Low' }, { minScore: 2, maxScore: 4, label: 'Moderate' }, { minScore: 5, label: 'High' }];
const scored = collectScoreItems(scoreUi as never);
add('scoring', 'collects only scored controls tagged by section', 'collectScoreItems', scoreUi);
add('scoring', 'sums ticked points with per-section subtotals', 'computeScore', scored, { age: { age75plus: true }, cardiovascular: { acuteMI: true } });
add('scoring', 'empty data scores zero', 'computeScore', scored, {});
add('scoring', 'false does not score', 'computeScore', scored, { age: { age41to60: false } });
// isPresent() accepted forms — the exact set matters. Note 'yes' scores but 'YES' does not.
for (const [label, v] of [['true', true], ['number 1', 1], ['string 1', '1'], ['string yes', 'yes'], ['string YES', 'YES'], ['positive number', 7], ['zero', 0], ['negative', -1], ['string no', 'no'], ['empty string', '']] as [string, unknown][]) {
  add('scoring', `isPresent via computeScore: ${label}`, 'computeScore', scored, { age: { age41to60: v } });
}
add('scoring', 'stratify low', 'stratify', 0, bands);
add('scoring', 'stratify moderate', 'stratify', 3, bands);
add('scoring', 'stratify high', 'stratify', 9, bands);
add('scoring', 'stratify without bands', 'stratify', 3, undefined);
add('scoring', 'scoreUiSchema resolves risk label', 'scoreUiSchema', scoreUi, { age: { age75plus: true }, cardiovascular: { acuteMI: true } }, bands);
add('scoring', 'scores the golden form (completed sample)', 'scoreUiSchema', ui, rrtSbarSampleCompleted, undefined);
add('scoring', 'scores the golden form (empty sample)', 'scoreUiSchema', ui, rrtSbarSampleEmpty, undefined);

// A scored SELECT: collected without omf.points, and contributing the points of
// whichever option is chosen.
// Morse Fall's "Ambulatory aid" — the choice carries the score, not a tick.
const ambulatoryAid = {
  type: 'Control',
  scope: '#/properties/morse/properties/aid',
  options: { omf: { optionPoints: { NONE: 0, CRUTCHES: 15, FURNITURE: 30 } } },
};
const aidSchema = { enum: ['NONE', 'CRUTCHES', 'FURNITURE'] };

const morse = { type: 'Group', label: 'MORSE FALL', elements: [ambulatoryAid] };
const morseItems = collectScoreItems(morse as never);
add('scoring', 'collects a scored select with no omf.points', 'collectScoreItems', morse);
add('scoring', 'contributes the selected choice points', 'computeScore', morseItems, { morse: { aid: 'CRUTCHES' } });
add('scoring', 'an unanswered select contributes nothing', 'computeScore', morseItems, {});
// Answered with the option worth nothing is NOT the same as unanswered: the
// section has been engaged, so it appears in bySection with a zero.
add('scoring', 'a zero-point choice still engages its section', 'computeScore', morseItems, { morse: { aid: 'NONE' } });
add('scoring', 'a code absent from the map contributes nothing', 'computeScore', morseItems, { morse: { aid: 'WHEELCHAIR' } });
add('scoring', 'a select-only section draws its own subtotal', 'showsSectionSubtotal', morse);

// showsSectionSubtotal — WHERE the automatic chip is drawn. Scoring itself is
// untouched by all of this; only the badge moves.
const qsofa = { type: 'Group', label: 'qSOFA', elements: [
  { type: 'Control', scope: '#/properties/q/properties/rr', options: { omf: { points: 1 } } },
] };
const sirs = { type: 'Group', label: 'SIRS', options: { omf: { bands: [{ maxScore: 1, label: 'Negative' }, { minScore: 2, label: 'Positive', color: '#b3392c' }] } }, elements: [
  { type: 'Control', scope: '#/properties/s/properties/temp', options: { omf: { points: 1 } } },
] };
const outerBox = { type: 'Group', label: 'Scoring Systems', elements: [qsofa, sirs] };
add('scoring', 'innermost scoring section draws the chip', 'showsSectionSubtotal', qsofa);
add('scoring', 'a box that merely contains scoring sections does not', 'showsSectionSubtotal', outerBox);
add('scoring', 'showSectionTotal puts it back on an outer box', 'showsSectionSubtotal', { ...outerBox, options: { omf: { showSectionTotal: true } } });
add('scoring', 'hideSectionTotal removes it from an innermost section', 'showsSectionSubtotal', { ...qsofa, options: { omf: { hideSectionTotal: true } } });
add('scoring', 'hideSectionTotal wins over showSectionTotal', 'showsSectionSubtotal', { ...qsofa, options: { omf: { showSectionTotal: true, hideSectionTotal: true } } });
add('scoring', 'a section with no scored items draws nothing', 'showsSectionSubtotal', { type: 'Group', label: 'Notes', elements: [{ type: 'Control', scope: '#/properties/notes' }] });

// elementBands — already ported, never replayed.
add('scoring', 'reads bands off a scored Group', 'elementBands', sirs);
add('scoring', 'no bands on a section without them', 'elementBands', qsofa);
add('scoring', 'a non-array bands value is ignored', 'elementBands', { type: 'Group', options: { omf: { bands: 'high' } } });
// A section's bands stratify that SECTION's subtotal — not the whole form's.
add('scoring', 'section subtotal picks its own band', 'computeScore', collectScoreItems(sirs as never), { s: { temp: true } }, elementBands(sirs as never));
add('scoring', 'section subtotal below the band threshold', 'computeScore', collectScoreItems(sirs as never), {}, elementBands(sirs as never));

// ---------------- enum_options ----------------
// Codes are stored; labels are read. Three ways a schema says what to show,
// and the points a scored CHOICE contributes.
const yesNoOneOf = { oneOf: [{ const: 'YES', title: 'Yes' }, { const: 'NO', title: 'No' }] };
const yesNoEnum = { enum: ['YES', 'NO'] };
const labelled = { options: { omf: { optionLabels: { YES: 'Ναι', NO: 'Όχι' } } } };
add('enum_options', 'oneOf titles win', 'resolveEnumOptions', yesNoOneOf, undefined);
add('enum_options', 'a bare enum shows the code', 'resolveEnumOptions', yesNoEnum, undefined);
add('enum_options', 'optionLabels name a bare enum', 'resolveEnumOptions', yesNoEnum, labelled);
add('enum_options', 'a oneOf title beats optionLabels', 'resolveEnumOptions', yesNoOneOf, labelled);
add('enum_options', 'numeric codes stringify', 'resolveEnumOptions', { enum: [1, 2] }, undefined);
add('enum_options', 'neither enum nor oneOf is not a choice', 'resolveEnumOptions', { type: 'string' }, undefined);
add('enum_options', 'no schema at all', 'resolveEnumOptions', undefined, undefined);
add('enum_options', 'optionPoints decorate each choice', 'resolveEnumOptions', aidSchema, ambulatoryAid);
add('enum_options', 'a zero-point choice keeps its zero', 'resolveEnumOptions', { enum: ['NONE'] }, ambulatoryAid);
add('enum_options', 'a code absent from optionPoints carries none', 'resolveEnumOptions', { enum: ['WHEELCHAIR'] }, ambulatoryAid);
add('enum_options', 'multi-enum reads items', 'resolveMultiEnumOptions', { type: 'array', items: yesNoOneOf }, undefined);
add('enum_options', 'multi-enum refuses tuple items', 'resolveMultiEnumOptions', { type: 'array', items: [yesNoOneOf] }, undefined);
add('enum_options', 'multi-enum on a non-array', 'resolveMultiEnumOptions', yesNoEnum, undefined);
add('enum_options', 'reads optionPoints off an element', 'elementOptionPoints', ambulatoryAid);
add('enum_options', 'no optionPoints on a plain control', 'elementOptionPoints', { type: 'Control' });

// ---------------- style ----------------
// The wash behind an accented callout. Flutter has its own Color type, so what
// has to match across renderers is the ARITHMETIC — which colours parse, and
// the 8% default alpha — not the CSS string these return.
for (const c of ['#b3392c', 'b3392c', '#f00', '#FFFFFF', '#000000']) {
  add('style', `parses ${c}`, 'parseHexColor', c);
}
for (const c of ['var(--bad)', 'rgb(1,2,3)', 'red', '#12345', '#b3392c80', '', undefined]) {
  add('style', `refuses ${c ?? 'undefined'} rather than guessing`, 'parseHexColor', c);
}
add('style', 'tint defaults to 8% of the accent', 'accentTint', '#b3392c');
add('style', 'tint honours an explicit alpha', 'accentTint', '#b3392c', 0.2);
add('style', 'tint is undefined when the accent is not hex', 'accentTint', 'var(--bad)');
add('style', 'opaque tint mixes against white', 'accentTintOpaque', '#b3392c');
add('style', 'opaque tint of white is white', 'accentTintOpaque', '#ffffff');
add('style', 'opaque tint darkens as alpha rises', 'accentTintOpaque', '#000000', 0.5);
add('style', 'opaque tint is undefined when the accent is not hex', 'accentTintOpaque', 'red');

// ---------------- record_table ----------------
add('record_table', 'reads a nested dot path', 'readRecordPath', { timelog: { cycle: '2' } }, 'timelog.cycle');
add('record_table', 'missing intermediate is undefined', 'readRecordPath', {}, 'timelog.cycle');
add('record_table', 'null intermediate is undefined', 'readRecordPath', { timelog: null }, 'timelog.cycle');
add('record_table', 'no path configured', 'readRecordPath', { a: 1 }, undefined);
add('record_table', 'plain value', 'recordCellText', { date: '2026-08-01' }, { label: 'Date', path: 'date' });
add('record_table', 'empty string is em dash', 'recordCellText', { nurse: '' }, { label: 'Nurse', path: 'nurse' });
add('record_table', 'null is em dash', 'recordCellText', { nurse: null }, { label: 'Nurse', path: 'nurse' });
add('record_table', 'missing is em dash', 'recordCellText', {}, { label: 'Nurse', path: 'nurse' });
add('record_table', 'counts a nested array', 'recordCellText', { adverseEvents: ['a', 'b'] }, { label: 'AE', countOf: 'adverseEvents' });
add('record_table', 'absent array counts zero not em dash', 'recordCellText', {}, { label: 'AE', countOf: 'adverseEvents' });
add('record_table', 'paired column joins with slash', 'recordCellText', { timelog: { cycle: '2', dayNum: '1' } }, { label: 'C/D', path: 'timelog.cycle', pairWith: 'timelog.dayNum' });
add('record_table', 'paired column em-dashes each half', 'recordCellText', { timelog: { cycle: '2' } }, { label: 'C/D', path: 'timelog.cycle', pairWith: 'timelog.dayNum' });
add('record_table', 'paired column both halves missing', 'recordCellText', {}, { label: 'C/D', path: 'timelog.cycle', pairWith: 'timelog.dayNum' });
add('record_table', 'boolean true renders Yes', 'recordCellText', { given: true }, { label: 'Given', path: 'given' });
add('record_table', 'boolean false renders No', 'recordCellText', { given: false }, { label: 'Given', path: 'given' });
add('record_table', 'numeric zero renders 0', 'recordCellText', { dose: 0 }, { label: 'Dose', path: 'dose' });
add('record_table', 'count template zero pluralises', 'recordCountText', '{n} treatment day{s} logged this month', 0);
add('record_table', 'count template one is singular', 'recordCountText', '{n} treatment day{s} logged this month', 1);
add('record_table', 'count template many pluralises', 'recordCountText', '{n} treatment day{s} logged this month', 3);
add('record_table', 'count fallback singular', 'recordCountText', undefined, 1);
add('record_table', 'count fallback plural', 'recordCountText', undefined, 2);
add('record_table', 'seeds nested objects and arrays but not scalars', 'createRecordDefault', { type: 'object', properties: { date: { type: 'string' }, timelog: { type: 'object', properties: { cycle: { type: 'string' } } }, adverseEvents: { type: 'array' } } });
add('record_table', 'honours explicit default', 'createRecordDefault', { type: 'object', properties: { status: { type: 'string', default: 'PLANNED' } } });
add('record_table', 'missing schema seeds empty record', 'createRecordDefault', undefined);
add('record_table', 'concrete path column is editable', 'isColumnEditable', { label: 'Date', path: 'date' });
add('record_table', 'countOf column is not editable', 'isColumnEditable', { label: 'Drugs', countOf: 'drugs' });
add('record_table', 'pairWith column is not editable', 'isColumnEditable', { label: 'S/F', path: 'a', pairWith: 'b' });
add('record_table', 'pathless column is not editable', 'isColumnEditable', { label: 'Nothing' });
const rtSchema = { type: 'object', properties: { day: {}, date: {}, grbs: {}, nurse: {} } };
add('record_table', 'lists fields outside columns', 'fieldsOutsideColumns', rtSchema, [{ label: 'Day', path: 'day' }]);
add('record_table', 'no fields left when all are columns', 'fieldsOutsideColumns', rtSchema, [{ label: 'Day', path: 'day' }, { label: 'Date', path: 'date' }, { label: 'GRBS', path: 'grbs' }, { label: 'Nurse', path: 'nurse' }]);
add('record_table', 'pairWith counts as shown', 'fieldsOutsideColumns', rtSchema, [{ label: 'D/D', path: 'day', pairWith: 'date' }]);
add('record_table', 'derives columns from an item schema', 'deriveRecordColumns', { type: 'object', properties: { a: { type: 'string', title: 'Alpha' }, b: { type: 'number' }, c: { type: 'string' }, d: { type: 'string' }, e: { type: 'string' } } });
// deriveRecordColumns humanises via summary.ts's own humanizeKey, which
// lowercases everything after the first character ('Inserted by'). That is NOT
// the same as the renderer's control-label humanisation ('Inserted By'), nor
// lodash startCase. Pin it so the difference cannot be ported away.
add('record_table', 'humanises camelCase keys, lowercasing after the first word', 'deriveRecordColumns', { type: 'object', properties: { insertedBy: { type: 'string' }, spo2Reading: { type: 'string' } } });
add('record_table', 'humanises snake_case and kebab-case keys', 'deriveRecordColumns', { type: 'object', properties: { grbs_value: { type: 'string' }, 'dose-given': { type: 'string' } } });
add('record_table', 'skips nested objects and arrays when deriving columns', 'deriveRecordColumns', { type: 'object', properties: { date: { type: 'string' }, timelog: { type: 'object' }, events: { type: 'array' }, nurse: { type: 'string' } } });
add('record_table', 'honours an explicit column limit', 'deriveRecordColumns', { type: 'object', properties: { a: { type: 'string' }, b: { type: 'string' }, c: { type: 'string' } } }, 2);
add('record_table', 'derives nothing from a missing schema', 'deriveRecordColumns', undefined);

// ---------------- serialization ----------------
add('serialization', 'nests objects without defaults', 'createEmptyResponse', ds, { applyDefaults: false });
add('serialization', 'applies schema defaults', 'createEmptyResponse', ds, undefined);
add('serialization', 'prunes empty leaves keeping false and zero', 'pruneEmptyValues', { a: '', b: null, d: { e: '' }, keepFalse: false, keepZero: 0, nested: { x: 1, y: '' } });
add('serialization', 'prunes array items element-wise', 'pruneEmptyValues', { list: [{ a: 1, b: '' }] });
add('serialization', 'serializes a completed response as valid', 'serializeForSubmit', ds, { ...rrtSbarSampleCompleted, reasonForCall: { ...(rrtSbarSampleCompleted.reasonForCall as object), other: '' } }, undefined);
add('serialization', 'reports errors for an invalid payload', 'serializeForSubmit', ds, { callDetails: { date: '2026-07-24' }, assessment: { spo2: 88 } }, undefined);

// ---------------- i18n ----------------
const tr = { defaultLanguage: 'en', languages: ['en', 'el'], entries: { 'assessment.avpu.ALERT': { en: 'Alert', el: 'Σε εγρήγορση' } } };
add('i18n', 'resolves requested language', 'resolveTranslation', tr, 'assessment.avpu.ALERT', 'el', undefined);
add('i18n', 'falls back to default language', 'resolveTranslation', tr, 'assessment.avpu.ALERT', 'fr', undefined);
add('i18n', 'falls back to caller fallback', 'resolveTranslation', tr, 'missing.key', 'el', 'Fallback');
add('i18n', 'falls back to the key itself', 'resolveTranslation', tr, 'missing.key', 'el', undefined);
add('i18n', 'hasLanguage true', 'hasLanguage', tr, 'el');
add('i18n', 'hasLanguage false', 'hasLanguage', tr, 'fr');

describe('conformance export', () => {
  it('writes fixture files', () => {
    mkdirSync(OUT, { recursive: true });

    for (const [module, cases] of Object.entries(files)) {
      const out = cases.map((c) => {
        const fn = CALL[c.fn];
        if (!fn) throw new Error(`no such fn ${c.fn}`);
        return { name: c.name, fn: c.fn, args: enc(c.args), expected: enc(fn(...(c.args as never[]))) };
      });
      writeFileSync(join(OUT, `${module}.json`), JSON.stringify({ module, sourceCommit: SHA, undefinedMarker: UNDEF, cases: out }, null, 2) + '\n');
    }

    // Validation: reduce Ajv errors to the comparable (instancePath, keyword) pairs.
    const vCases = [
      { name: 'empty sample is incomplete (required missing)', schema: ds, data: rrtSbarSampleEmpty },
      { name: 'completed sample is valid', schema: ds, data: rrtSbarSampleCompleted },
      { name: 'low spo2 requires a recommendation (if/then)', schema: ds, data: { callDetails: { date: '2026-07-24' }, assessment: { spo2: 88 } } },
      { name: 'wrong type for integer field', schema: ds, data: { assessment: { spo2: 'ninety' } } },
      { name: 'bad date format', schema: { type: 'object', properties: { d: { type: 'string', format: 'date' } } }, data: { d: 'not-a-date' } },
      { name: 'good date format', schema: { type: 'object', properties: { d: { type: 'string', format: 'date' } } }, data: { d: '2026-08-01' } },
      { name: 'required keyword', schema: { type: 'object', properties: { a: { type: 'string' } }, required: ['a'] }, data: {} },
      { name: 'enum keyword', schema: { type: 'object', properties: { a: { enum: ['X', 'Y'] } } }, data: { a: 'Z' } },
      { name: 'maximum keyword', schema: { type: 'object', properties: { a: { type: 'integer', maximum: 5 } } }, data: { a: 9 } },
      { name: 'minLength keyword', schema: { type: 'object', properties: { a: { type: 'string', minLength: 3 } } }, data: { a: 'ab' } },
      { name: 'additionalProperties false', schema: { type: 'object', properties: { a: {} }, additionalProperties: false }, data: { a: 1, b: 2 } },
      { name: '$ref to $defs', schema: { $defs: { P: { type: 'object', properties: { n: { type: 'integer' } } } }, type: 'object', properties: { p: { $ref: '#/$defs/P' } } }, data: { p: { n: 'x' } } },
    ];
    const vOut = vCases.map((c) => {
      const r = validateData(c.schema as never, c.data);
      return {
        name: c.name,
        fn: 'validateData',
        args: enc([c.schema, c.data]),
        expected: { valid: r.valid, errors: r.errors.map((e) => ({ instancePath: e.instancePath, keyword: e.keyword })).sort((a, b) => (a.instancePath + a.keyword).localeCompare(b.instancePath + b.keyword)) },
      };
    });
    writeFileSync(join(OUT, 'validation.json'), JSON.stringify({ module: 'validation', sourceCommit: SHA, undefinedMarker: UNDEF, note: 'Compare `valid` and the sorted (instancePath, keyword) pairs only. Ajv message text is validator-specific and is deliberately not part of the contract.', cases: vOut }, null, 2) + '\n');

    // Registry tester ranks.
    const el = (o: unknown) => o as never;
    const regCases = [
      { name: 'byOmfControl matches', fn: 'byOmfControl', args: ['recordTable'], element: { type: 'Control', options: { omf: { control: 'recordTable' } } } },
      { name: 'byOmfControl does not match a different control', fn: 'byOmfControl', args: ['recordTable'], element: { type: 'Control', options: { omf: { control: 'scoreSummary' } } } },
      { name: 'byOmfControl does not match a bare control', fn: 'byOmfControl', args: ['recordTable'], element: { type: 'Control' } },
      { name: 'byOmfLayout matches', fn: 'byOmfLayout', args: ['OmfTabsLayout'], element: { type: 'OmfTabsLayout' } },
      { name: 'byType matches', fn: 'byType', args: ['Group'], element: { type: 'Group' } },
      { name: 'bySchemaType matches string control', fn: 'bySchemaType', args: ['string'], element: { type: 'Control' }, context: { fieldSchema: { type: 'string' } } },
      { name: 'bySchemaType matches a union type array', fn: 'bySchemaType', args: ['string'], element: { type: 'Control' }, context: { fieldSchema: { type: ['string', 'null'] } } },
      { name: 'bySchemaType rejects a non-control', fn: 'bySchemaType', args: ['string'], element: { type: 'Group' }, context: { fieldSchema: { type: 'string' } } },
    ];
    const TESTERS: Record<string, (...a: never[]) => (e: never, c?: never) => number> = { byOmfControl, byOmfLayout, byType, bySchemaType } as never;
    const rOut = regCases.map((c) => ({
      name: c.name, fn: c.fn, args: enc(c.args), element: enc(c.element), context: enc(c.context),
      expected: TESTERS[c.fn](...(c.args as never[]))(el(c.element), el(c.context)),
    }));
    writeFileSync(join(OUT, 'registry.json'), JSON.stringify({ module: 'registry', sourceCommit: SHA, notApplicable: NOT_APPLICABLE, emptyCell: EMPTY_CELL, controlNames: [...OMF_CONTROL_NAMES], cases: rOut }, null, 2) + '\n');

    // Golden form + samples, verbatim.
    mkdirSync(join(OUT, 'golden'), { recursive: true });
    writeFileSync(join(OUT, 'golden', 'rrt-sbar.definition.json'), JSON.stringify(rrtSbarReference, null, 2) + '\n');
    writeFileSync(join(OUT, 'golden', 'rrt-sbar.sample-empty.json'), JSON.stringify(rrtSbarSampleEmpty, null, 2) + '\n');
    writeFileSync(join(OUT, 'golden', 'rrt-sbar.sample-completed.json'), JSON.stringify(rrtSbarSampleCompleted, null, 2) + '\n');
  });
});
