import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateTenants, repoRoot } from '../src/validate.ts';
import { contrast } from '../src/contrast.ts';
import { tenantCss } from '../src/css.ts';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

test('every tenant file passes', () => {
  const results = validateTenants();
  assert.ok(results.length >= 2, 'expected at least two tenants (real + dummy)');
  for (const r of results) assert.deepEqual(r.errors, [], r.file);
});

test('contrast maths matches WCAG reference values', () => {
  assert.equal(contrast('#000000', '#FFFFFF').toFixed(1), '21.0');
  assert.equal(contrast('#5E0202', '#FFFFFF').toFixed(2), '14.14');
});

test('css output carries brand values', () => {
  const t = JSON.parse(readFileSync(join(repoRoot(), 'tenants/realtime-estates.json'), 'utf8'));
  const css = tenantCss(t);
  assert.match(css, /--color-primary: #5E0202;/);
  assert.match(css, /--font-display: "Poppins"/);
});

test('unreadable colours are rejected', async () => {
  const { contrastProblems } = await import('../src/contrast.ts');
  const t = JSON.parse(readFileSync(join(repoRoot(), 'tenants/realtime-estates.json'), 'utf8'));
  const bad = { ...t.brand.colors, textMuted: '#AAAAAA', error: '#FF0000' };
  const problems = contrastProblems(bad);
  assert.equal(problems.length, 2);
  assert.match(problems.join(' '), /textMuted on surface/);
});
