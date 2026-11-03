import { test } from 'node:test';
import assert from 'node:assert/strict';
import { areasTarget, startingAreas } from './areas';

test('sixteen starting areas, valid, with no demo figures', () => {
  const a = startingAreas();
  assert.equal(a.length, 16);
  assert.equal(new Set(a.map((x) => x.id)).size, 16);
  for (const x of a) assert.deepEqual(x.data.stats, { medianRentKES: null, listings: 0 });
});

test('a production project must be named twice', () => {
  assert.ok('error' in areasTarget({}));
  assert.ok('error' in areasTarget({ PROJECT: 'Bad Id' }));
  assert.deepEqual(areasTarget({ PROJECT: 'demo-project-dev' }), { projectId: 'demo-project-dev' });
  assert.deepEqual(areasTarget({ PROJECT: 'demo-project-stage' }), { projectId: 'demo-project-stage' });
  assert.match((areasTarget({ PROJECT: 'demo-project-prod' }) as { error: string }).error, /CONFIRM=demo-project-prod/);
  assert.ok('error' in areasTarget({ PROJECT: 'demo-project-prod', CONFIRM: 'demo-project-dev' }));
  assert.deepEqual(areasTarget({ PROJECT: 'demo-project-prod', CONFIRM: 'demo-project-prod' }), { projectId: 'demo-project-prod' });
});
