/**
 * Cross-renderer parity harness — the React half.
 *
 * ADR-003 requires that the same form, filled the same way, produces the same
 * submission payload in every renderer. This mounts the **React** renderer,
 * replays a scripted sequence of clinician interactions, and writes the payload
 * each step produced. The Dart half replays the identical script against the
 * Flutter renderer and asserts the payloads match, step for step.
 *
 * Comparing step by step rather than only at the end matters: two renderers can
 * disagree in the middle — one writing `false` where the other deletes a key —
 * and still land on the same final object.
 *
 * This file is TypeScript and does not run in the Flutter repository. It runs
 * inside the openmedform monorepo, which owns the React renderer. Like
 * `conformance_export.ts`, it is staged here so the fixture stays reproducible.
 *
 * Usage, from a checkout of daivahealth/openmedform:
 *
 *   cp tool/parity_export.tsx \
 *      <openmedform>/packages/react-form-renderer/src/__parity_export.test.tsx
 *   cd <openmedform>/packages/react-form-renderer
 *   OMF_PARITY_OUT=<this-repo>/packages/openmedform_flutter_renderer/test/parity \
 *     ./node_modules/.bin/vitest run src/__parity_export.test.tsx
 *   rm <openmedform>/packages/react-form-renderer/src/__parity_export.test.tsx
 */
import { describe, it } from 'vitest';
import { render, fireEvent, screen, cleanup } from '@testing-library/react';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { JsonFormsRenderer } from './engine/jsonforms/JsonFormsRenderer';

const OUT = process.env.OMF_PARITY_OUT!;

/** One scripted clinician action. Both harnesses understand these. */
type Step =
  | { action: 'fillText'; label: string; value: string }
  | { action: 'fillNumber'; label: string; value: string }
  | { action: 'check'; label: string }
  | { action: 'uncheck'; label: string }
  | { action: 'selectOption'; label: string; value: string }
  | { action: 'chooseRadio'; label: string; value: string }
  | { action: 'toggleMatrixCell'; row: string; column: string }
  | { action: 'toggleScoringItem'; label: string };

const dataSchema = {
  type: 'object',
  properties: {
    ward: { type: 'string', title: 'Ward' },
    handover: { type: 'string', title: 'Handover' },
    spo2: { type: 'integer', title: 'SpO2' },
    sepsis: { type: 'boolean', title: 'Sepsis' },
    avpu: { type: 'string', title: 'AVPU', enum: ['ALERT', 'VOICE', 'PAIN'] },
    anticoagulant: { type: 'string', title: 'On anticoagulants', enum: ['YES', 'NO'] },
    rounds: { type: 'object', title: 'Rounds' },
    vte: { type: 'object', title: 'VTE risk' },
  },
} as never;

const control = (property: string, omf?: Record<string, unknown>) => ({
  type: 'Control',
  scope: `#/properties/${property}`,
  ...(omf ? { options: { omf } } : {}),
});

const uiSchema = {
  schemaVersion: '1.0',
  layout: {
    type: 'VerticalLayout',
    elements: [
      control('ward'),
      control('handover', { control: 'textarea' }),
      control('spo2'),
      control('sepsis', { points: 3 }),
      control('avpu'),
      control('anticoagulant', { control: 'radio' }),
      control('rounds', {
        control: 'checklistMatrix',
        rows: [
          { key: 'pressure', label: 'Pressure area care' },
          { key: 'mouth', label: 'Mouth care' },
        ],
        columns: [
          { key: 'd1', label: 'Day 1' },
          { key: 'd2', label: 'Day 2' },
        ],
      }),
      control('vte', {
        control: 'scoringMatrix',
        domains: [
          {
            name: 'Mobility',
            items: [
              { field: 'bedrest', label: 'Bed rest', points: 1 },
              { field: 'immobile', label: 'Immobile', points: 3 },
            ],
          },
        ],
      }),
    ],
  },
} as never;

/**
 * The script. Ordered so the interesting disagreements are forced:
 * a cleared field, an unchecked box, an unchecked matrix cell.
 */
const steps: Step[] = [
  { action: 'fillText', label: 'Ward', value: 'ICU 3' },
  { action: 'fillText', label: 'Handover', value: 'Deteriorating overnight' },
  { action: 'fillNumber', label: 'SpO2', value: '88' },
  { action: 'check', label: 'Sepsis' },
  { action: 'selectOption', label: 'AVPU', value: 'VOICE' },
  { action: 'chooseRadio', label: 'On anticoagulants', value: 'YES' },
  { action: 'toggleMatrixCell', row: 'Pressure area care', column: 'Day 1' },
  { action: 'toggleMatrixCell', row: 'Pressure area care', column: 'Day 2' },
  // Unchecking must DELETE the key, not write false.
  { action: 'toggleMatrixCell', row: 'Pressure area care', column: 'Day 1' },
  { action: 'toggleScoringItem', label: 'Immobile' },
  { action: 'toggleScoringItem', label: 'Bed rest' },
  // Clearing a field must remove it, not store an empty string.
  { action: 'fillText', label: 'Ward', value: '' },
  // Unchecking a plain boolean.
  { action: 'uncheck', label: 'Sepsis' },
];

/** Find the input a label points at. */
function inputFor(label: string): HTMLElement {
  const node = screen.getByLabelText(label, { exact: false });
  return node as HTMLElement;
}

function apply(step: Step): void {
  switch (step.action) {
    case 'fillText':
    case 'fillNumber':
      fireEvent.change(inputFor(step.label), { target: { value: step.value } });
      return;
    case 'check':
    case 'uncheck':
      fireEvent.click(inputFor(step.label));
      return;
    case 'selectOption':
      fireEvent.change(inputFor(step.label), { target: { value: step.value } });
      return;
    case 'chooseRadio': {
      const radios = screen.getAllByRole('radio') as HTMLInputElement[];
      const match = radios.find((r) => r.value === step.value);
      if (!match) throw new Error(`no radio option ${step.value}`);
      fireEvent.click(match);
      return;
    }
    case 'toggleMatrixCell': {
      const cell = screen.getByLabelText(`${step.row} — ${step.column}`);
      fireEvent.click(cell);
      return;
    }
    case 'toggleScoringItem': {
      const row = screen.getByText(step.label).closest('tr');
      if (!row) throw new Error(`no scoring row ${step.label}`);
      const box = row.querySelector('input[type="checkbox"]');
      if (!box) throw new Error(`no checkbox for ${step.label}`);
      fireEvent.click(box);
      return;
    }
  }
}

describe('cross-renderer parity export', () => {
  it('records the payload after each scripted interaction', () => {
    mkdirSync(OUT, { recursive: true });

    let latest: Record<string, unknown> = {};
    render(
      <JsonFormsRenderer
        definition={{ dataSchema, uiSchema } as never}
        onChange={(data) => {
          latest = data;
        }}
      />,
    );

    const trace: { step: Step; payload: Record<string, unknown> }[] = [];
    for (const step of steps) {
      apply(step);
      // Structured-clone the payload so later mutations cannot rewrite history.
      trace.push({ step, payload: JSON.parse(JSON.stringify(latest)) });
    }

    cleanup();

    writeFileSync(
      join(OUT, 'parity_trace.json'),
      JSON.stringify(
        {
          note:
            'Generated by tool/parity_export.tsx against the React renderer. ' +
            'The Dart test replays the same steps and must produce the same ' +
            'payload after every one.',
          dataSchema,
          uiSchema,
          trace,
        },
        null,
        2,
      ) + '\n',
    );
  });
});
