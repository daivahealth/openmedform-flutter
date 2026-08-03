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
 * as a proper `form-core` script (see PLAN.md → follow-ups).
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
  toPathSegments, getValueAtPath, setValueAtPath, deleteValueAtPath, getValueAtScope, setValueAtScope,
  evaluateCondition, evaluateRule, evaluateElementState,
  collectScoreItems, computeScore, stratify, scoreUiSchema,
  readRecordPath, recordCellText, recordCountText, createRecordDefault, deriveRecordColumns,
  isColumnEditable, fieldsOutsideColumns, EMPTY_CELL,
  createEmptyResponse, pruneEmptyValues, serializeForSubmit,
  validateData,
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
  toPathSegments, getValueAtPath, setValueAtPath, deleteValueAtPath, getValueAtScope, setValueAtScope,
  evaluateCondition, evaluateRule, evaluateElementState,
  collectScoreItems, computeScore, stratify, scoreUiSchema,
  readRecordPath, recordCellText, recordCountText, createRecordDefault, deriveRecordColumns,
  isColumnEditable, fieldsOutsideColumns,
  createEmptyResponse, pruneEmptyValues, serializeForSubmit,
  resolveTranslation, hasLanguage,
} as never;

const ds = rrtSbarReference.dataSchema;
const ui = rrtSbarReference.uiSchema;

// ---------------- pointer ----------------
add('pointer', 'simple scope to data path', 'scopeToDataPath', '#/properties/situation');
add('pointer', 'nested scope keeps every other segment', 'scopeToDataPath', '#/properties/assessment/properties/spo2');
add('pointer', 'nested scope to segments', 'scopeToDataPathSegments', '#/properties/assessment/properties/spo2');
add('pointer', 'schema segments retain properties keyword', 'scopeToSchemaSegments', '#/properties/assessment/properties/spo2');
add('pointer', 'root scope', 'scopeToDataPath', '#');
add('pointer', 'resolves schema at scope', 'resolveSchemaAtScope', ds, '#/properties/assessment/properties/spo2');
add('pointer', 'resolves schema through $ref/$defs', 'resolveSchemaAtScope', ds, '#/properties/callDetails');
add('pointer', 'unknown scope resolves to undefined', 'resolveSchemaAtScope', ds, '#/properties/nope/properties/missing');
add('pointer', 'derefSchema on a $ref node', 'derefSchema', ds, { $ref: '#/$defs/CallDetails' });
add('pointer', 'derefSchema passes through a plain node', 'derefSchema', ds, { type: 'string' });

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
    writeFileSync(join(OUT, 'registry.json'), JSON.stringify({ module: 'registry', sourceCommit: SHA, notApplicable: NOT_APPLICABLE, emptyCell: EMPTY_CELL, cases: rOut }, null, 2) + '\n');

    // Golden form + samples, verbatim.
    mkdirSync(join(OUT, 'golden'), { recursive: true });
    writeFileSync(join(OUT, 'golden', 'rrt-sbar.definition.json'), JSON.stringify(rrtSbarReference, null, 2) + '\n');
    writeFileSync(join(OUT, 'golden', 'rrt-sbar.sample-empty.json'), JSON.stringify(rrtSbarSampleEmpty, null, 2) + '\n');
    writeFileSync(join(OUT, 'golden', 'rrt-sbar.sample-completed.json'), JSON.stringify(rrtSbarSampleCompleted, null, 2) + '\n');
  });
});
