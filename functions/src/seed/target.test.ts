import { test } from 'node:test';
import assert from 'node:assert/strict';
import { seedTarget } from './target';

test('the emulator is always allowed', () => {
  assert.deepEqual(seedTarget({ FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080' }), { projectId: 'demo-realtor', emulator: true });
});

test('a real project only when named and ending in -dev', () => {
  assert.deepEqual(seedTarget({ SEED_PROJECT: 'rte-realtor-dev' }), { projectId: 'rte-realtor-dev', emulator: false });
  assert.ok('error' in seedTarget({}));
  assert.ok('error' in seedTarget({ SEED_PROJECT: 'rte-realtor-prod' }));
  assert.ok('error' in seedTarget({ SEED_PROJECT: 'rte-realtor-stage' }));
  assert.ok('error' in seedTarget({ SEED_PROJECT: 'rte-realtor-dev-but-prod' }));
});
