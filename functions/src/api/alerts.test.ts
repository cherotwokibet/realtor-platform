import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matches } from './alerts';

const flat = { id: 'l1', slug: 's', title: 't', purpose: 'rent', type: 'apartment', area: 'kilimani', beds: 2, priceKES: 60000 };

test('a saved search matches on purpose, type, area, beds and top price', () => {
  assert.ok(matches({ purpose: 'rent' }, flat));
  assert.ok(matches({ purpose: 'rent', types: ['apartment', 'studio'], areas: ['kilimani'], minBeds: 2, maxPriceKES: 60000 }, flat));
  assert.ok(!matches({ purpose: 'sale' }, flat));
  assert.ok(!matches({ purpose: 'rent', areas: ['westlands'] }, flat));
  assert.ok(!matches({ purpose: 'rent', minBeds: 3 }, flat));
  assert.ok(!matches({ purpose: 'rent', maxPriceKES: 59999 }, flat));
  assert.ok(matches({ purpose: 'rent', types: [], areas: [] }, flat), 'empty lists mean any');
});
