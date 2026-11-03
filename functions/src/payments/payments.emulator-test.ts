/**
 * M-Pesa payments against the Firestore emulator, with a scripted Daraja:
 *   firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run test:emulator"
 */
import { before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import type { DarajaConfig } from './daraja';
import { type PaymentDeps, reconcilePayments, recordStkCallback, startViewingPayment } from './payments';

let db: Firestore;
const now = new Date('2026-11-03T09:00:00Z');
const daraja: DarajaConfig = { env: 'sandbox', shortcode: '174379', type: 'paybill', consumerKey: 'k', consumerSecret: 's', passkey: 'pk' };

/** Daraja stand-in: token, then pushes and queries answered from a script. */
function fakeDaraja(script: Record<string, unknown[]> = {}) {
  const calls: string[] = [];
  let n = 0;
  const fn = (async (url: string) => {
    const path = new URL(url).pathname;
    calls.push(path);
    if (path.startsWith('/oauth')) return Response.json({ access_token: 'tok' });
    const next = script[path]?.shift();
    if (next) return Response.json(next);
    if (path.endsWith('/processrequest')) return Response.json({ ResponseCode: '0', CheckoutRequestID: `ws_CO_${++n}`, MerchantRequestID: `m${n}` });
    return Response.json({}, { status: 500 });
  }) as unknown as typeof fetch;
  const deps: PaymentDeps = { daraja, callbackUrl: 'https://europe-west1-demo.cloudfunctions.net/payments-mpesaCallback', fetch: fn };
  return { deps, calls };
}

async function rejectsWith(p: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(p, (e: { code?: string }) => e.code === code || assert.fail(`expected ${code}, got ${e.code}: ${e}`));
}

const paidCallback = (checkoutRequestId: string, amount = 500) => ({
  checkoutRequestId,
  outcome: { status: 'paid' as const, receipt: 'TK31ABCDEF', amountKES: amount },
});

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run inside firebase emulators:exec');
  if (!getApps().length) initializeApp({ projectId: 'demo-realtor' });
  db = getFirestore();
});

beforeEach(async () => {
  for (const c of ['payments', 'viewings', 'config']) {
    const all = await db.collection(c).get();
    await Promise.all(all.docs.map((d) => d.ref.delete()));
  }
  await db.collection('config').doc('tenant').set({ features: { mpesa: true } });
  const base = { listingId: 'listing-001', agentId: 'agent-wanjiku', slot: now, client: { name: 'Amina', phone: '+254712345678' }, paymentId: null, createdAt: now };
  await db.collection('viewings').doc('v-fee').set({ ...base, status: 'requested', feeKES: 500 });
  await db.collection('viewings').doc('v-free').set({ ...base, status: 'requested', feeKES: 0 });
  await db.collection('viewings').doc('v-gone').set({ ...base, status: 'cancelled', feeKES: 500 });
});

const payment = async (id = 'viewing-fee_v-fee') => (await db.collection('payments').doc(id).get()).data()!;

describe('startViewingPayment', () => {
  test('pushes the viewing fee from the viewing, not from the client', async () => {
    const d = fakeDaraja();
    const r = await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678', amountKES: 1 }, d.deps, now);
    assert.deepEqual(r, { paymentId: 'viewing-fee_v-fee', status: 'pending' });
    const p = await payment();
    assert.equal(p.amountKES, 500);
    assert.equal(p.status, 'pending');
    assert.equal(p.checkoutRequestId, 'ws_CO_1');
    assert.match(p.callbackToken, /^[0-9a-f]{48}$/);
    assert.deepEqual(d.calls, ['/oauth/v1/generate', '/mpesa/stkpush/v1/processrequest']);
  });

  test('refuses when M-Pesa is off, the viewing has no fee, or is not open', async () => {
    const d = fakeDaraja();
    await rejectsWith(startViewingPayment(db, { viewingId: 'v-free', phone: '+254712345678' }, d.deps, now), 'failed-precondition');
    await rejectsWith(startViewingPayment(db, { viewingId: 'v-gone', phone: '+254712345678' }, d.deps, now), 'not-found');
    await rejectsWith(startViewingPayment(db, { viewingId: 'v-fee', phone: '0712345678' }, d.deps, now), 'invalid-argument');
    await db.collection('config').doc('tenant').set({ features: { mpesa: false } });
    await rejectsWith(startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now), 'failed-precondition');
    assert.deepEqual(d.calls, [], 'Daraja never called');
  });

  test('a second tap within 2 minutes reuses the push; later it pushes again; paid cannot pay twice', async () => {
    const d = fakeDaraja();
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now);
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, new Date(now.getTime() + 60_000));
    assert.equal(d.calls.filter((c) => c.endsWith('processrequest')).length, 1);
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, new Date(now.getTime() + 3 * 60_000));
    const p = await payment();
    assert.equal(p.checkoutRequestId, 'ws_CO_2');
    assert.equal(p.attempts, 2);
    assert.equal(await recordStkCallback(db, paidCallback('ws_CO_2'), p.callbackToken, now), 'recorded');
    await rejectsWith(startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, new Date(now.getTime() + 10 * 60_000)), 'already-exists');
  });

  test('a refused push marks the payment failed', async () => {
    const d = fakeDaraja({ '/mpesa/stkpush/v1/processrequest': [{ errorMessage: 'Bad Request - Invalid PhoneNumber' }] });
    await rejectsWith(startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now), 'unavailable');
    const p = await payment();
    assert.equal(p.status, 'failed');
    assert.match(p.reason, /Invalid PhoneNumber/);
  });
});

describe('recordStkCallback', () => {
  test('paid: receipt recorded and the viewing points at the payment; repeats change nothing', async () => {
    const d = fakeDaraja();
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now);
    const token = (await payment()).callbackToken;
    assert.equal(await recordStkCallback(db, paidCallback('ws_CO_1'), token, now), 'recorded');
    const p = await payment();
    assert.equal(p.status, 'paid');
    assert.equal(p.receipt, 'TK31ABCDEF');
    assert.equal((await db.collection('viewings').doc('v-fee').get()).get('paymentId'), 'viewing-fee_v-fee');
    assert.equal(await recordStkCallback(db, { checkoutRequestId: 'ws_CO_1', outcome: { status: 'failed', reason: 'x' } }, token, now), 'ignored');
    assert.equal((await payment()).status, 'paid');
  });

  test('wrong token, unknown push, or a different amount do not mark it paid', async () => {
    const d = fakeDaraja();
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now);
    const token = (await payment()).callbackToken;
    assert.equal(await recordStkCallback(db, paidCallback('ws_CO_1'), 'not-the-token', now), 'ignored');
    assert.equal(await recordStkCallback(db, paidCallback('ws_CO_404'), token, now), 'ignored');
    assert.equal(await recordStkCallback(db, null, token, now), 'ignored');
    assert.equal((await payment()).status, 'pending');
    assert.equal(await recordStkCallback(db, paidCallback('ws_CO_1', 5), token, now), 'recorded');
    const p = await payment();
    assert.equal(p.status, 'failed');
    assert.match(p.reason, /KES 5, expected KES 500/);
    assert.equal((await db.collection('viewings').doc('v-fee').get()).get('paymentId'), null);
  });

  test('cancelled on the phone', async () => {
    const d = fakeDaraja();
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now);
    const token = (await payment()).callbackToken;
    await recordStkCallback(db, { checkoutRequestId: 'ws_CO_1', outcome: { status: 'cancelled', reason: 'Request cancelled by user' } }, token, now);
    assert.equal((await payment()).status, 'cancelled');
  });
});

describe('reconcilePayments', () => {
  test('asks Daraja about pushes pending over 3 minutes, and gives up after a day', async () => {
    const d = fakeDaraja({
      '/mpesa/stkpushquery/v1/query': [{ ResponseCode: '0', ResultCode: '0', ResultDesc: 'ok' }],
    });
    await startViewingPayment(db, { viewingId: 'v-fee', phone: '+254712345678' }, d.deps, now);
    assert.deepEqual(await reconcilePayments(db, d.deps, new Date(now.getTime() + 60_000)), { checked: 0, settled: 0 }, 'too young');
    assert.deepEqual(await reconcilePayments(db, d.deps, new Date(now.getTime() + 4 * 60_000)), { checked: 1, settled: 1 });
    const p = await payment();
    assert.equal(p.status, 'paid');
    assert.equal(p.receipt, null, 'the query gives no receipt; the statement has it');

    await db.collection('payments').doc('stuck').set({ ...p, status: 'pending', checkoutRequestId: 'ws_CO_9', createdAt: now });
    const later = fakeDaraja({ '/mpesa/stkpushquery/v1/query': [{ errorCode: '500.001.1001', errorMessage: 'The transaction is being processed' }] });
    assert.deepEqual(await reconcilePayments(db, later.deps, new Date(now.getTime() + 10 * 60_000)), { checked: 1, settled: 0 });
    const dayLater = fakeDaraja({ '/mpesa/stkpushquery/v1/query': [{ errorCode: '500.001.1001' }] });
    await reconcilePayments(db, dayLater.deps, new Date(now.getTime() + 25 * 3_600_000));
    assert.equal((await payment('stuck')).status, 'failed');
  });
});
