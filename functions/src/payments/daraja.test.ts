import { test } from 'node:test';
import assert from 'node:assert/strict';
import { darajaTimestamp, darajaToken, msisdn, outcomeOf, parseStkCallback, stkPassword, stkPush, stkQuery, type DarajaConfig } from './daraja';
import { mpesaConfig, callbackUrl } from './config';

const cfg: DarajaConfig = { env: 'sandbox', shortcode: '174379', type: 'paybill', consumerKey: 'k', consumerSecret: 's', passkey: 'pk' };

/** A fetch that records calls and answers from a script. */
function fakeFetch(answers: { status?: number; body: unknown }[]) {
  const calls: { url: string; init?: RequestInit }[] = [];
  const fn = (async (url: string, init?: RequestInit) => {
    calls.push({ url, init });
    const a = answers.shift() ?? { status: 500, body: {} };
    return new Response(JSON.stringify(a.body), { status: a.status ?? 200 });
  }) as unknown as typeof fetch;
  return { fn, calls };
}

test('timestamp is Nairobi time; password is base64(shortcode + passkey + timestamp)', () => {
  assert.equal(darajaTimestamp(new Date('2026-11-03T21:05:09Z')), '20261104000509');
  assert.equal(stkPassword('174379', 'pk', '20261104000509'), Buffer.from('174379pk20261104000509').toString('base64'));
  assert.equal(msisdn('+254712345678'), '254712345678');
  assert.throws(() => msisdn('0712345678'));
});

test('token: basic auth to the sandbox; a refusal is an error', async () => {
  const f = fakeFetch([{ body: { access_token: 'tok', expires_in: '3599' } }, { status: 400, body: {} }]);
  assert.equal(await darajaToken(cfg, f.fn), 'tok');
  assert.match(f.calls[0].url, /^https:\/\/sandbox\.safaricom\.co\.ke\/oauth\/v1\/generate\?grant_type=client_credentials$/);
  assert.equal((f.calls[0].init?.headers as Record<string, string>).authorization, `Basic ${Buffer.from('k:s').toString('base64')}`);
  await assert.rejects(darajaToken(cfg, f.fn), /sign-in failed/);
});

test('STK Push sends what Daraja needs and returns the checkout id', async () => {
  const f = fakeFetch([{ body: { ResponseCode: '0', CheckoutRequestID: 'ws_CO_1', MerchantRequestID: 'm1' } }]);
  const r = await stkPush(
    cfg,
    'tok',
    { amountKES: 500, phone: '+254712345678', callbackUrl: 'https://x/cb?t=abc', accountReference: 'Viewing fee long', description: 'Viewing fee for a home' },
    new Date('2026-11-03T09:00:00Z'),
    f.fn,
  );
  assert.deepEqual(r, { checkoutRequestId: 'ws_CO_1', merchantRequestId: 'm1' });
  const sent = JSON.parse(String(f.calls[0].init?.body));
  assert.equal(sent.TransactionType, 'CustomerPayBillOnline');
  assert.equal(sent.Amount, 500);
  assert.equal(sent.PartyA, '254712345678');
  assert.equal(sent.Timestamp, '20261103120000');
  assert.equal(sent.AccountReference.length, 12);
  assert.ok(sent.TransactionDesc.length <= 13);
  const till = fakeFetch([{ body: { ResponseCode: '0', CheckoutRequestID: 'ws_CO_2' } }]);
  await stkPush({ ...cfg, type: 'till' }, 't', { amountKES: 1, phone: '+254112345678', callbackUrl: 'u', accountReference: 'a', description: 'd' }, new Date(), till.fn);
  assert.equal(JSON.parse(String(till.calls[0].init?.body)).TransactionType, 'CustomerBuyGoodsOnline');
});

test('STK Push refuses bad amounts and reports Daraja errors', async () => {
  const f = fakeFetch([{ status: 400, body: { errorMessage: 'Bad Request - Invalid PhoneNumber' } }]);
  const req = { amountKES: 0, phone: '+254712345678', callbackUrl: 'u', accountReference: 'a', description: 'd' };
  await assert.rejects(stkPush(cfg, 't', req, new Date(), f.fn), /KES 1 to/);
  await assert.rejects(stkPush(cfg, 't', { ...req, amountKES: 250_001 }, new Date(), f.fn), /KES 1 to/);
  await assert.rejects(stkPush(cfg, 't', { ...req, amountKES: 10 }, new Date(), f.fn), /Invalid PhoneNumber/);
});

test('callbacks: paid with receipt and amount, cancelled, failed, junk', () => {
  const paid = parseStkCallback({
    Body: {
      stkCallback: {
        MerchantRequestID: 'm1',
        CheckoutRequestID: 'ws_CO_1',
        ResultCode: 0,
        ResultDesc: 'The service request is processed successfully.',
        CallbackMetadata: { Item: [{ Name: 'Amount', Value: 500 }, { Name: 'MpesaReceiptNumber', Value: 'TK31ABCDEF' }, { Name: 'PhoneNumber', Value: 254712345678 }] },
      },
    },
  });
  assert.deepEqual(paid, { checkoutRequestId: 'ws_CO_1', outcome: { status: 'paid', receipt: 'TK31ABCDEF', amountKES: 500 } });
  assert.equal(parseStkCallback({ Body: { stkCallback: { CheckoutRequestID: 'x', ResultCode: 1032, ResultDesc: 'Request cancelled by user' } } })?.outcome.status, 'cancelled');
  assert.equal(parseStkCallback({ Body: { stkCallback: { CheckoutRequestID: 'x', ResultCode: 1, ResultDesc: 'Insufficient balance' } } })?.outcome.status, 'failed');
  assert.equal(parseStkCallback({ hello: 'world' }), null);
  assert.equal(parseStkCallback(null), null);
  assert.equal(outcomeOf('1037', '').status, 'failed');
});

test('query: result codes, and "still being processed" is pending', async () => {
  const f = fakeFetch([
    { body: { ResponseCode: '0', ResultCode: '0', ResultDesc: 'ok' } },
    { status: 500, body: { errorCode: '500.001.1001', errorMessage: 'The transaction is being processed' } },
    { body: { ResponseCode: '0', ResultCode: '1032', ResultDesc: 'Request cancelled by user' } },
    { status: 500, body: { errorCode: '404.001.03', errorMessage: 'Invalid Access Token' } },
  ]);
  assert.equal((await stkQuery(cfg, 't', 'ws_CO_1', new Date(), f.fn)).status, 'paid');
  assert.equal((await stkQuery(cfg, 't', 'ws_CO_1', new Date(), f.fn)).status, 'pending');
  assert.equal((await stkQuery(cfg, 't', 'ws_CO_1', new Date(), f.fn)).status, 'cancelled');
  await assert.rejects(stkQuery(cfg, 't', 'ws_CO_1', new Date(), f.fn), /Invalid Access Token/);
});

test('config: off unless MPESA_ENV is set; checks the shortcode and type', () => {
  assert.equal(mpesaConfig({}), null);
  assert.deepEqual(mpesaConfig({ MPESA_ENV: 'sandbox', MPESA_SHORTCODE: '174379' }), { env: 'sandbox', shortcode: '174379', type: 'paybill' });
  assert.throws(() => mpesaConfig({ MPESA_ENV: 'live', MPESA_SHORTCODE: '174379' }), /sandbox or production/);
  assert.throws(() => mpesaConfig({ MPESA_ENV: 'sandbox', MPESA_SHORTCODE: 'secret://x' }), /5 to 7 digit/);
  assert.throws(() => mpesaConfig({ MPESA_ENV: 'sandbox', MPESA_SHORTCODE: '174379', MPESA_TYPE: 'bank' }), /paybill or till/);
  assert.equal(callbackUrl('rte-realtor-dev', 'europe-west1'), 'https://europe-west1-rte-realtor-dev.cloudfunctions.net/payments-mpesaCallback');
});
