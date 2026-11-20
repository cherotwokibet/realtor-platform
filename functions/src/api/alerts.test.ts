import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matches, parseArea, pushFor } from './alerts';

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

test('a drawn area matches only the homes inside it', () => {
  // A square around Kilimani; the home sits in it, a Westlands one does not.
  const square = '-1.28,36.77~-1.28,36.8~-1.3,36.8~-1.3,36.77';
  const inKili = { ...flat, lat: -1.29, lng: 36.785 };
  assert.ok(matches({ purpose: 'rent', poly: square }, inKili));
  assert.ok(!matches({ purpose: 'rent', poly: square }, { ...flat, lat: -1.265, lng: 36.8 }));
  assert.ok(!matches({ purpose: 'rent', poly: square }, flat), 'a home with no position cannot be in an area');
  assert.ok(!matches({ purpose: 'rent', poly: '-1.28,36.77~-1.28,36.8' }, inKili), 'too few corners matches nothing');
  assert.ok(!matches({ purpose: 'rent', poly: `${square}~x,y` }, inKili), 'junk corners match nothing');
  assert.equal(parseArea('-1.28,36.77~-1.28,36.8~-1.3,36.8')?.length, 3);
});
