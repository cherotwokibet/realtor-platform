import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { contrastProblems } from '../src/contrast.ts';
import { derivePalette, rebrandTenant } from '../src/rebrand.ts';
import { repoRoot, validateTenants } from '../src/validate.ts';

function scratch(): string {
  const root = mkdtempSync(join(tmpdir(), 'rebrand-'));
  for (const d of ['tenants', 'brand', 'fonts']) cpSync(join(repoRoot(), d), join(root, d), { recursive: true });
  return root;
}

const DEMO = 'demo-homes';
const base = JSON.parse(readFileSync(join(repoRoot(), 'tenants', `${DEMO}.json`), 'utf8')).brand.colors;

test('any brand colour gives a palette that passes every contrast check', () => {
  for (const [primary, accent] of [
    ['#0B5D1E', undefined],
    ['#FFD700', '#00BFFF'], // bright yellow and sky blue: both need help
    ['#E30613', '#FFFFFF'],
    ['#000000', '#222222'],
    ['#7FDBFF', undefined],
  ] as const) {
    const { colors } = derivePalette(base, primary, accent);
    assert.deepEqual(contrastProblems(colors), [], `${primary} / ${accent}`);
  }
});

test('a readable brand colour is kept as given; an unreadable one is darkened and said so', () => {
  assert.equal(derivePalette(base, '#0b5d1e').colors.primary, '#0B5D1E');
  assert.deepEqual(derivePalette(base, '#0B5D1E').notes, []);
  const yellow = derivePalette(base, '#FFD700');
  assert.notEqual(yellow.colors.primary, '#FFD700');
  assert.match(yellow.notes[0], /^primary #FFD700 → #[0-9A-F]{6}/);
});

test('rebrand makes a valid tenant from the demo, under the new name and colours', () => {
  const root = scratch();
  const { tenantFile } = rebrandTenant(root, 'acme-demo', 'Acme Realty', { from: DEMO, primary: '#B00020' });
  assert.deepEqual(validateTenants(root, ['acme-demo'])[0].errors, []);
  const t = JSON.parse(readFileSync(tenantFile, 'utf8'));
  const demo = JSON.parse(readFileSync(join(root, 'tenants', `${DEMO}.json`), 'utf8'));
  assert.equal(t.name, 'Acme Realty');
  assert.equal(t.brand.colors.primary, '#B00020');
  assert.deepEqual(t.features, demo.features);
  assert.deepEqual(t.brand.fonts, demo.brand.fonts);
  assert.ok(Object.values(t.brand.logo).every((p) => (p as string).startsWith('brand/acme-demo/')));
  assert.equal(readdirSync(join(root, 'brand', 'acme-demo')).length, 7);
  assert.ok(!JSON.stringify(t).includes('Demo Homes'), 'nothing of the demo name is left');
});

test('refuses bad colours, bad ids and existing tenants', () => {
  const root = scratch();
  assert.throws(() => rebrandTenant(root, 'acme-demo', 'Acme', { from: DEMO, primary: 'red' }), /--primary must be/);
  assert.throws(() => rebrandTenant(root, 'Acme', 'Acme', { from: DEMO, primary: '#B00020' }), /id must be/);
  assert.throws(() => rebrandTenant(root, DEMO, 'Again', { from: DEMO, primary: '#B00020' }), /already exists/);
});
