import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, readFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createTenant } from '../src/create.ts';
import { repoRoot, validateTenants } from '../src/validate.ts';

/** A scratch repo with the real tenants/ folder, so tests never touch the checkout. */
function scratch(): string {
  const root = mkdtempSync(join(tmpdir(), 'create-'));
  cpSync(join(repoRoot(), 'tenants'), join(root, 'tenants'), { recursive: true });
  cpSync(join(repoRoot(), 'brand'), join(root, 'brand'), { recursive: true });
  cpSync(join(repoRoot(), 'fonts'), join(root, 'fonts'), { recursive: true });
  return root;
}

test('a created tenant validates straight away', () => {
  const root = scratch();
  const { tenantFile } = createTenant(root, 'acme-realty', 'Acme Realty Ltd');
  const [r] = validateTenants(root, ['acme-realty']);
  assert.deepEqual(r.errors, []);
  const t = JSON.parse(readFileSync(tenantFile, 'utf8'));
  assert.equal(t.name, 'Acme Realty Ltd');
  assert.equal(t.apps.androidId, 'com.example.acmerealty');
  assert.deepEqual(t.firebase.projects, { dev: 'acme-realty-dev', stage: 'acme-realty-stage', prod: 'acme-realty-prod' });
  assert.equal(readdirSync(join(root, 'brand', 'acme-realty')).length, 7);
});

test('placeholder art has no <text> (renders the same everywhere)', () => {
  const root = scratch();
  const { brandDir } = createTenant(root, 'acme-realty', 'Acme Realty Ltd');
  for (const f of readdirSync(brandDir)) assert.doesNotMatch(readFileSync(join(brandDir, f), 'utf8'), /<text/, f);
});

test('refuses an existing tenant and bad ids', () => {
  const root = scratch();
  assert.throws(() => createTenant(root, 'demo-homes', 'Again'), /already exists/);
  assert.throws(() => createTenant(root, 'Acme', 'Acme'), /id must be/);
  assert.throws(() => createTenant(root, 'a-very-long-tenant-id-indeed', 'Long'), /id must be/);
});

test('longest allowed id still makes valid GCP project ids', () => {
  const root = scratch();
  createTenant(root, 'abcdefghijklmnopqrstuvwx', 'Long Name Ltd');
  assert.deepEqual(validateTenants(root, ['abcdefghijklmnopqrstuvwx'])[0].errors, []);
});
