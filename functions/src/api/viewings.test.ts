import { test } from 'node:test';
import assert from 'node:assert/strict';
import { slotProblem } from './viewings';

// Monday 26 Oct 2026, 09:00 in Nairobi (06:00 UTC).
const now = new Date('2026-10-26T06:00:00Z');
const at = (iso: string) => slotProblem(new Date(iso), now);

test('open slots: Mon-Sat, 08:00-17:30 Nairobi time, on the half hour', () => {
  assert.equal(at('2026-10-27T10:30:00+03:00'), null);
  assert.equal(at('2026-10-27T08:00:00+03:00'), null, 'first slot');
  assert.equal(at('2026-10-27T17:30:00+03:00'), null, 'last slot');
  assert.equal(at('2026-10-31T09:00:00+03:00'), null, 'Saturday');
  assert.equal(at('2026-10-27T07:30:00Z'), null, 'any offset works: 10:30 Nairobi');
});

test('closed slots say why', () => {
  assert.match(at('2026-11-01T10:00:00+03:00')!, /Sundays/);
  assert.match(at('2026-10-27T07:30:00+03:00')!, /8:00 to 18:00/);
  assert.match(at('2026-10-27T18:00:00+03:00')!, /8:00 to 18:00/);
  assert.match(at('2026-10-27T10:15:00+03:00')!, /30-minute mark/);
  assert.match(at('2026-10-26T10:00:00+03:00')!, /2 hours ahead/, 'only an hour away');
  assert.match(at('2026-10-20T10:00:00+03:00')!, /2 hours ahead/, 'in the past');
  assert.match(at('2026-11-30T10:00:00+03:00')!, /within 30 days/);
  assert.equal(slotProblem(new Date('nope'), now), 'not a date');
});
