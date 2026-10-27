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

test('every tenant font is bundled in all four weights', async () => {
  const { tenantFontFiles } = await import('../src/fonts.ts');
  const t = JSON.parse(readFileSync(join(repoRoot(), 'tenants/realtime-estates.json'), 'utf8'));
  const files = tenantFontFiles(t);
  assert.deepEqual([...new Set(files.map((f) => f.family))], ['Poppins', 'Inter']);
  assert.equal(files.length, 8);
  assert.ok(files.some((f) => f.source === 'fonts/Inter/Inter-SemiBold.ttf' && f.weight === 600));
});

test('a font that is not bundled fails validation', async () => {
  const { fontProblems } = await import('../src/fonts.ts');
  const t = JSON.parse(readFileSync(join(repoRoot(), 'tenants/demo-homes.json'), 'utf8'));
  assert.deepEqual(fontProblems(repoRoot(), t), []);
  const bad = { ...t, brand: { ...t.brand, fonts: { display: 'Plus Jakarta Sans', body: 'Manrope' } } };
  const problems = fontProblems(repoRoot(), bad);
  assert.equal(problems.length, 4);
  assert.match(problems[0], /fonts\/PlusJakartaSans\/PlusJakartaSans-Regular\.ttf/);
});

test('store ids for App Links / Universal Links are optional and checked', () => {
  const schema = JSON.parse(readFileSync(join(repoRoot(), 'tenants/schema/tenant.schema.json'), 'utf8'));
  const apps = schema.properties.apps.properties;
  const fp = new RegExp(apps.androidCertSha256.items.pattern);
  assert.ok(fp.test('14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:8A:04:96:B2:3F:CF:44:E5'));
  assert.ok(!fp.test('14:6d:e9'), 'full upper-case SHA-256 only');
  assert.ok(new RegExp(apps.appleTeamId.pattern).test('ABCDE12345'));
  assert.ok(!new RegExp(apps.appleTeamId.pattern).test('abc'));
  assert.ok(!schema.properties.apps.required.includes('androidCertSha256'));
});
