import { test } from 'node:test';
import assert from 'node:assert/strict';
import { purposeOn, requirePurposeOn } from './features';

test('a purpose is on unless its switch is explicitly false', () => {
  const f = { rent: true, sale: false, shortStay: false };
  assert.equal(purposeOn(f, 'rent'), true);
  assert.equal(purposeOn(f, 'sale'), false);
  assert.equal(purposeOn(f, 'short-stay'), false, 'short-stay maps to shortStay');
  assert.equal(purposeOn({}, 'sale'), true, 'a missing key keeps it on');
});

test('no config/tenant yet: nothing is switched off', () => {
  for (const p of ['rent', 'sale', 'short-stay'] as const) assert.equal(purposeOn(null, p), true);
});

test('requirePurposeOn refuses with failed-precondition', () => {
  assert.throws(() => requirePurposeOn({ shortStay: false }, 'short-stay'), (e: { code?: string }) => e.code === 'failed-precondition');
  assert.doesNotThrow(() => requirePurposeOn({ shortStay: true }, 'short-stay'));
});
