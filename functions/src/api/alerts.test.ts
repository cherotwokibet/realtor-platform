import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matches, pushFor } from './alerts';

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

test('one push per person: one home opens it, several open the inbox', () => {
  assert.deepEqual(pushFor([{ ...flat, title: '2 bed in Kilimani' }]), {
    title: 'A new home matches your search',
    body: '2 bed in Kilimani, KES 60,000 a month',
    path: '/listing/s',
  });
  const many = pushFor([flat, { ...flat, id: 'l2', purpose: 'sale', priceKES: 9_500_000 }, { ...flat, id: 'l3' }]);
  assert.equal(many.title, '3 new homes match your searches');
  assert.equal(many.body, 't, KES 60,000 a month, and 2 more');
  assert.equal(many.path, '/account');
  assert.equal(pushFor([{ ...flat, purpose: 'sale', priceKES: 9_500_000 }]).body, 't, KES 9,500,000');
});
