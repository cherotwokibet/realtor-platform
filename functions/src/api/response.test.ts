import { test } from 'node:test';
import assert from 'node:assert/strict';
import { median } from './response';

test('median of reply times: middle value, or the rounded mean of the two middle ones', () => {
  assert.equal(median([]), null);
  assert.equal(median([12]), 12);
  assert.equal(median([30, 5, 600]), 30);
  assert.equal(median([10, 20, 30, 41]), 25);
  assert.equal(median([10, 20, 31, 41]), 26); // 25.5 rounds up
});
