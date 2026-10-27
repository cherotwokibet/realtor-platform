import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seedTarget } from './target';

test('the emulator is always allowed', () => {
  assert.deepEqual(seedTarget({ FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' }), { projectId: 'demo-realtor', emulator: true });
});

test('a real project only when named and ending in -dev', () => {
  assert.deepEqual(seedTarget({ SEED_PROJECT: 'acme-realty-dev' }), { projectId: 'acme-realty-dev', emulator: false });
  assert.ok('error' in seedTarget({}));
  assert.ok('error' in seedTarget({ SEED_PROJECT: 'acme-realty-prod' }));
  assert.ok('error' in seedTarget({ SEED_PROJECT: 'acme-realty-stage' }));
  assert.ok('error' in seedTarget({ SEED_PROJECT: 'acme-realty-dev-but-prod' }));
});
