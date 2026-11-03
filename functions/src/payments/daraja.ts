/**
 * Safaricom Daraja (M-Pesa Express / STK Push, P6-s01): the HTTP calls and
 * the pure helpers around them. No Firestore here; payments.ts holds the
 * money logic. fetch is injected so tests never reach Safaricom.
 */

export type DarajaEnv = 'sandbox' | 'production';
export type ShortcodeType = 'paybill' | 'till';
type Fetch = typeof fetch;

export const DARAJA_BASE: Record<DarajaEnv, string> = {
  sandbox: 'https://sandbox.safaricom.co.ke',
  production: 'https://api.safaricom.co.ke',
};

/** M-Pesa's per-transaction ceiling for STK Push (KES). */
export const MAX_STK_KES = 250_000;

export interface DarajaConfig {
  env: DarajaEnv;
  shortcode: string;
  type: ShortcodeType;
  consumerKey: string;
  consumerSecret: string;
  passkey: string;
}

/** YYYYMMDDHHmmss in Nairobi time (UTC+3, no daylight saving), as Daraja wants. */
export function darajaTimestamp(now: Date): string {
  const t = new Date(now.getTime() + 3 * 3_600_000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${t.getUTCFullYear()}${p(t.getUTCMonth() + 1)}${p(t.getUTCDate())}${p(t.getUTCHours())}${p(t.getUTCMinutes())}${p(t.getUTCSeconds())}`;
}

export const stkPassword = (shortcode: string, passkey: string, timestamp: string) =>
  Buffer.from(`${shortcode}${passkey}${timestamp}`).toString('base64');

/** +254712345678 -> 254712345678 (Daraja wants no plus). */
export function msisdn(e164: string): string {
  if (!/^\+254[17]\d{8}$/.test(e164)) throw new Error('a Kenyan mobile number is needed, e.g. +254712345678');
  return e164.slice(1);
}

export async function darajaToken(c: DarajaConfig, fetchFn: Fetch = fetch): Promise<string> {
  const auth = Buffer.from(`${c.consumerKey}:${c.consumerSecret}`).toString('base64');
  const res = await fetchFn(`${DARAJA_BASE[c.env]}/oauth/v1/generate?grant_type=client_credentials`, { headers: { authorization: `Basic ${auth}` } });
  if (!res.ok) throw new Error(`Daraja sign-in failed (${res.status})`);
  const body = (await res.json()) as { access_token?: string };
  if (!body.access_token) throw new Error('Daraja sign-in gave no token');
  return body.access_token;
}

export interface StkRequest {
  amountKES: number;
  phone: string;
  callbackUrl: string;
  /** Shown on the customer's phone; Daraja keeps 12 characters. */
  accountReference: string;
  description: string;
}

export async function stkPush(
  c: DarajaConfig,
  token: string,
  r: StkRequest,
  now: Date,
  fetchFn: Fetch = fetch,
): Promise<{ checkoutRequestId: string; merchantRequestId: string }> {
  if (!Number.isInteger(r.amountKES) || r.amountKES < 1 || r.amountKES > MAX_STK_KES) throw new Error(`amount must be KES 1 to ${MAX_STK_KES}`);
  const timestamp = darajaTimestamp(now);
  const res = await fetchFn(`${DARAJA_BASE[c.env]}/mpesa/stkpush/v1/processrequest`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      BusinessShortCode: c.shortcode,
      Password: stkPassword(c.shortcode, c.passkey, timestamp),
      Timestamp: timestamp,
      TransactionType: c.type === 'till' ? 'CustomerBuyGoodsOnline' : 'CustomerPayBillOnline',
      Amount: r.amountKES,
      PartyA: msisdn(r.phone),
      PartyB: c.shortcode,
      PhoneNumber: msisdn(r.phone),
      CallBackURL: r.callbackUrl,
      AccountReference: r.accountReference.slice(0, 12),
      TransactionDesc: r.description.slice(0, 13),
    }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, string>;
  if (!res.ok || body.ResponseCode !== '0' || !body.CheckoutRequestID) {
    throw new Error(`STK Push refused (${res.status}): ${body.errorMessage ?? body.ResponseDescription ?? 'no reason given'}`);
  }
  return { checkoutRequestId: body.CheckoutRequestID, merchantRequestId: body.MerchantRequestID ?? '' };
}

export type StkOutcome =
  | { status: 'paid'; receipt: string | null; amountKES: number | null }
  | { status: 'cancelled' | 'failed'; reason: string }
  | { status: 'pending' };

/** Daraja's ResultCode -> our status. 1032: cancelled on the phone; 1037: no answer; anything else non-zero: failed. */
export function outcomeOf(resultCode: number | string, resultDesc: string): StkOutcome {
  const code = Number(resultCode);
  if (code === 0) return { status: 'paid', receipt: null, amountKES: null };
  if (code === 1032) return { status: 'cancelled', reason: resultDesc || 'cancelled on the phone' };
  return { status: 'failed', reason: resultDesc || `M-Pesa result ${code}` };
}

export interface StkCallback {
  checkoutRequestId: string;
  outcome: StkOutcome;
}

/** The body Safaricom POSTs to the callback URL, or null when it isn't one. */
export function parseStkCallback(body: unknown): StkCallback | null {
  const cb = (body as { Body?: { stkCallback?: Record<string, unknown> } })?.Body?.stkCallback;
  if (!cb || typeof cb.CheckoutRequestID !== 'string' || cb.ResultCode === undefined) return null;
  const outcome = outcomeOf(cb.ResultCode as number, String(cb.ResultDesc ?? ''));
  if (outcome.status === 'paid') {
    const items = ((cb.CallbackMetadata as { Item?: { Name: string; Value?: unknown }[] })?.Item ?? []).reduce<Record<string, unknown>>(
      (m, i) => ({ ...m, [i.Name]: i.Value }),
      {},
    );
    outcome.receipt = typeof items.MpesaReceiptNumber === 'string' ? items.MpesaReceiptNumber : null;
    outcome.amountKES = typeof items.Amount === 'number' ? items.Amount : null;
  }
  return { checkoutRequestId: cb.CheckoutRequestID, outcome };
}

/** Asks Daraja how a push ended (reconciliation). "Still being processed" is pending. */
export async function stkQuery(c: DarajaConfig, token: string, checkoutRequestId: string, now: Date, fetchFn: Fetch = fetch): Promise<StkOutcome> {
  const timestamp = darajaTimestamp(now);
  const res = await fetchFn(`${DARAJA_BASE[c.env]}/mpesa/stkpushquery/v1/query`, {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({
      BusinessShortCode: c.shortcode,
      Password: stkPassword(c.shortcode, c.passkey, timestamp),
      Timestamp: timestamp,
      CheckoutRequestID: checkoutRequestId,
    }),
  });
  const body = (await res.json().catch(() => ({}))) as Record<string, string>;
  if (body.ResultCode !== undefined) return outcomeOf(body.ResultCode, body.ResultDesc ?? '');
  // Daraja answers 500.001.1001 "The transaction is being processed" while the customer decides.
  if (String(body.errorCode ?? '').startsWith('500.001.1001')) return { status: 'pending' };
  throw new Error(`STK query failed (${res.status}): ${body.errorMessage ?? 'no reason given'}`);
}
