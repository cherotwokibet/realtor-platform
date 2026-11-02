import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { seedTenantId, tenantConfigDoc } from './tenant';

// Made-up tenants: no real tenant's identifiers in code or tests.
function repo(): string {
  const root = mkdtempSync(join(tmpdir(), 'seed-tenant-'));
  mkdirSync(join(root, 'tenants'));
  const write = (id: string, extra: object) =>
    writeFileSync(join(root, 'tenants', `${id}.json`), JSON.stringify({ id, name: 'Secret Name', features: { rent: true, shortStay: id === 'beta-realty' }, ...extra }));
  write('beta-realty', {});
  write('alpha-homes', { contact: { email: 'a@example.com' } });
  return root;
}

test('seeds SEED_TENANT, else the first tenant file by name', () => {
  const root = repo();
  assert.equal(seedTenantId({}, root), 'alpha-homes');
  assert.equal(seedTenantId({ SEED_TENANT: 'beta-realty' }, root), 'beta-realty');
  assert.throws(() => seedTenantId({ SEED_TENANT: '../etc/passwd' }, root));
});

test('config/tenant carries only the id and the feature switches', () => {
  const root = repo();
  const doc = tenantConfigDoc(root, 'alpha-homes');
  assert.deepEqual(Object.keys(doc).sort(), ['features', 'id']);
  assert.equal(doc.features.shortStay, false);
  assert.equal(tenantConfigDoc(root, 'beta-realty').features.shortStay, true);
});
