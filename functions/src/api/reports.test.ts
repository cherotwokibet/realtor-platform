import { test } from 'node:test';
import assert from 'node:assert/strict';
import { monthRange } from './reports';

test('a report month is the Nairobi calendar month (UTC+3)', () => {
  const { start, end } = monthRange('2026-10');
  assert.equal(start.toISOString(), '2026-09-30T21:00:00.000Z');
  assert.equal(end.toISOString(), '2026-10-31T21:00:00.000Z');
  assert.equal(monthRange('2026-12').end.toISOString(), '2026-12-31T21:00:00.000Z');
});
