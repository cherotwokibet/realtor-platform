import { test } from 'node:test';
import assert from 'node:assert/strict';
import type { Request, Response } from 'express';
import { HttpsError } from 'firebase-functions/v2/https';
import { callableTwin, enforced, sharePagesInvoker, twinName } from './appcheck';

test('ENFORCE_APP_CHECK names the callables to enforce; unset enforces none', () => {
  assert.deepEqual([...enforced({})], []);
  assert.deepEqual([...enforced({ ENFORCE_APP_CHECK: 'createLead, logContactTap,setStaffRole' })], ['createLead', 'logContactTap']);
  assert.deepEqual([...enforced({ ENFORCE_APP_CHECK: 'all' })], ['createLead', 'bookViewing', 'logContactTap', 'submitReview']);
});

test('twin names and invoker', () => {
  assert.equal(twinName('createLead'), 'shareCreateLead');
  assert.equal(twinName('logContactTap'), 'shareLogContactTap');
  assert.equal(sharePagesInvoker('demo-project'), 'share-pages@demo-project.iam.gserviceaccount.com');
});

async function call(handler: (d: unknown) => Promise<unknown>, method: string, reqBody: unknown) {
  const out: { status?: number; json?: unknown } = {};
  const res = {
    status(s: number) { out.status = s; return this; },
    json(j: unknown) { out.json = j; return this; },
  } as unknown as Response;
  await callableTwin(handler)({ method, body: reqBody } as Request, res);
  return out;
}

test('a twin answers like a callable', async () => {
  const seen: unknown[] = [];
  assert.deepEqual(await call(async (d) => { seen.push(d); return { id: 'lead-1' }; }, 'POST', { data: { a: 1 } }), { status: 200, json: { result: { id: 'lead-1' } } });
  assert.deepEqual(seen, [{ a: 1 }]);

  const bad = await call(async () => { throw new HttpsError('resource-exhausted', 'slow down'); }, 'POST', { data: {} });
  assert.equal(bad.status, 429);
  assert.deepEqual(bad.json, { error: { status: 'RESOURCE_EXHAUSTED', message: 'slow down' } });

  assert.equal((await call(async () => 1, 'GET', undefined)).status, 400);
  assert.equal((await call(async () => 1, 'POST', 'nope')).status, 400);
  const boom = await call(async () => { throw new Error('secret detail'); }, 'POST', { data: {} });
  assert.deepEqual(boom, { status: 500, json: { error: { status: 'INTERNAL', message: 'internal' } } });
});
