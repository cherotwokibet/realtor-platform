import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { seedTenantId, tenantConfigDoc } from './tenant';

// lib/seed -> repo root
const root = join(__dirname, '..', '..', '..');

test('seeds the demo tenant unless SEED_TENANT names another', () => {
  assert.equal(seedTenantId({}), 'demo-homes');
  assert.equal(seedTenantId({ SEED_TENANT: 'realtime-estates' }), 'realtime-estates');
  assert.throws(() => seedTenantId({ SEED_TENANT: '../etc/passwd' }));
});

test('config/tenant carries only the id and the feature switches', () => {
  const doc = tenantConfigDoc(root, 'realtime-estates');
  assert.deepEqual(Object.keys(doc).sort(), ['features', 'id']);
  assert.equal(doc.features.shortStay, false);
  assert.equal(tenantConfigDoc(root, 'demo-homes').features.shortStay, true);
});
