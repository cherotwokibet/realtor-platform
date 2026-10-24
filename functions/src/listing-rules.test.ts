import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canMove, verificationExpiry, isValidKes } from './listing-rules';

test('verification lasts 30 days', () => {
  const d = verificationExpiry(new Date('2026-10-01T00:00:00Z'));
  assert.equal(d.toISOString(), '2026-10-31T00:00:00.000Z');
});

test('status moves', () => {
  assert.ok(canMove('pending', 'live'));
  assert.ok(!canMove('draft', 'live'), 'drafts must go through approval');
  assert.ok(!canMove('sold', 'live'));
});

test('KES amounts', () => {
  assert.ok(isValidKes(65000));
  assert.ok(!isValidKes(650.5));
  assert.ok(!isValidKes(-1));
  assert.ok(!isValidKes('65000'));
});
