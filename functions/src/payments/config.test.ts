import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mpesaConfig } from './config';

const base = { MPESA_ENV: 'sandbox', MPESA_SHORTCODE: '174379' };

test('featured price is optional and a whole number of shillings', () => {
  assert.equal(mpesaConfig(base)?.featuredPerDayKES, null);
  assert.equal(mpesaConfig({ ...base, FEATURED_PER_DAY_KES: '250' })?.featuredPerDayKES, 250);
  assert.equal(mpesaConfig({ ...base, FEATURED_PER_DAY_KES: '0' })?.featuredPerDayKES, null);
  assert.throws(() => mpesaConfig({ ...base, FEATURED_PER_DAY_KES: '2.5' }), /whole number/);
  assert.throws(() => mpesaConfig({ ...base, FEATURED_PER_DAY_KES: '-1' }), /whole number/);
});

test('no MPESA_ENV means payments are off', () => assert.equal(mpesaConfig({}), null));
