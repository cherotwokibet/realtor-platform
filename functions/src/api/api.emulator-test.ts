/**
 * Callable API against the Firestore emulator:
 *   firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run test:emulator"
 */
import { before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { seedDocs } from '../seed/data';
import type { Caller } from './auth';
import { createLead, logContactTap, updateLeadStage, LEAD_RETENTION_DAYS } from './leads';
import { moderateListing, submitListing } from './listings';
import { bookViewing } from './viewings';

let db: Firestore;
const visitor: Caller = { uid: null, role: null, agentId: null };
const wanjiku: Caller = { uid: 'u1', role: 'agent', agentId: 'agent-wanjiku' };
const otieno: Caller = { uid: 'u2', role: 'agent', agentId: 'agent-otieno' };
const manager: Caller = { uid: 'm1', role: 'manager', agentId: null };
const now = new Date('2026-10-24T09:00:00Z');

/** Asserts the promise rejects with this HttpsError code. */
async function rejectsWith(p: Promise<unknown>, code: string): Promise<void> {
  await assert.rejects(p, (e: { code?: string }) => e.code === code || assert.fail(`expected ${code}, got ${e.code}: ${e}`));
}

before(() => {
  assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'run inside firebase emulators:exec');
  initializeApp({ projectId: 'demo-realtor' });
  db = getFirestore();
});

beforeEach(async () => {
  for (const c of ['listings', 'leads', 'areas', 'agents', 'viewings']) {
    const all = await db.collection(c).get();
    await Promise.all(all.docs.map((d) => d.ref.delete()));
  }
  const batch = db.batch();
  for (const d of seedDocs(now)) batch.set(db.collection(d.collection).doc(d.id), d.data);
  await batch.commit();
});

const newListing = {
  title: '2 bedroom apartment, Kilimani',
  purpose: 'rent',
  type: 'apartment',
  beds: 2,
  baths: 2,
  priceKES: 70000,
  depositMonths: 2,
  lat: -1.2905,
  lng: 36.786,
  area: 'kilimani',
};

describe('bookViewing', () => {
  // `now` is Saturday 24 Oct 2026, 12:00 Nairobi; Monday 26 Oct 10:30 is open.
  const slot = '2026-10-26T10:30:00+03:00';
  const amina = { name: 'Amina', phone: '+254700000401' };

  test('books a slot with the listing agent and stores the client as a consented lead', async () => {
    const { viewingId, leadId } = await bookViewing(db, { listingId: 'listing-001', slot, client: amina, consent: true }, now);
    assert.equal(viewingId, `agent-wanjiku_${new Date(slot).getTime()}`);
    const v = (await db.collection('viewings').doc(viewingId).get()).data()!;
    assert.equal(v.status, 'requested');
    assert.equal(v.agentId, 'agent-wanjiku');
    assert.equal(v.slot.toDate().toISOString(), '2026-10-26T07:30:00.000Z');
    const l = (await db.collection('leads').doc(leadId).get()).data()!;
    assert.equal(l.channel, 'viewing');
    assert.deepEqual(l.contact, amina);
    assert.equal(l.retainUntil.toDate().getTime() - l.consentAt.toDate().getTime(), LEAD_RETENTION_DAYS * 86_400_000);
  });

  test('one active booking per agent per slot; a cancelled slot frees up', async () => {
    await bookViewing(db, { listingId: 'listing-001', slot, client: amina, consent: true }, now);
    // listing-004 has the same agent (every third listing): same slot is taken.
    await rejectsWith(bookViewing(db, { listingId: 'listing-004', slot, client: { name: 'Juma', phone: '+254700000402' }, consent: true }, now), 'already-exists');
    // A different agent at the same time is fine.
    await bookViewing(db, { listingId: 'listing-002', slot, client: { name: 'Juma', phone: '+254700000402' }, consent: true }, now);
    await db.collection('viewings').doc(`agent-wanjiku_${new Date(slot).getTime()}`).update({ status: 'cancelled' });
    await bookViewing(db, { listingId: 'listing-004', slot, client: { name: 'Juma', phone: '+254700000402' }, consent: true }, now);
  });

  test('refuses closed slots, missing consent and unavailable listings', async () => {
    const ok = { listingId: 'listing-001', slot, client: amina, consent: true };
    await rejectsWith(bookViewing(db, { ...ok, slot: '2026-10-25T10:30:00+03:00' }, now), 'invalid-argument'); // Sunday
    await rejectsWith(bookViewing(db, { ...ok, slot: '2026-10-26 10:30' }, now), 'invalid-argument'); // no offset
    await rejectsWith(bookViewing(db, { ...ok, consent: false }, now), 'invalid-argument');
    await rejectsWith(bookViewing(db, { ...ok, client: { name: 'A', phone: '0712345678' } }, now), 'invalid-argument');
    await rejectsWith(bookViewing(db, { ...ok, listingId: 'no-such-listing' }, now), 'not-found');
    assert.equal((await db.collection('viewings').count().get()).data().count, 0);
  });
});

describe('logContactTap', () => {
  test('counts call and WhatsApp taps on the listing and stores no lead', async () => {
    const leadsBefore = (await db.collection('leads').count().get()).data().count;
    await logContactTap(db, { listingId: 'listing-001', channel: 'whatsapp' });
    await logContactTap(db, { listingId: 'listing-001', channel: 'whatsapp' });
    await logContactTap(db, { listingId: 'listing-001', channel: 'call' });
    const stats = (await db.collection('listings').doc('listing-001').get()).get('stats');
    assert.equal(stats.whatsapps, 2);
    assert.equal(stats.calls, 1);
    assert.equal((await db.collection('leads').count().get()).data().count, leadsBefore);
  });

  test('refuses unknown listings and channels', async () => {
    await rejectsWith(logContactTap(db, { listingId: 'no-such-listing', channel: 'call' }), 'not-found');
    await rejectsWith(logContactTap(db, { listingId: 'listing-001', channel: 'sms' }), 'invalid-argument');
  });
});

describe('createLead', () => {
  test('stores consent, retention and the listing agent; counts the lead', async () => {
    const { leadId } = await createLead(db, { listingId: 'listing-001', channel: 'form', contact: { phone: '+254700000301' }, consent: true }, now);
    const l = (await db.collection('leads').doc(leadId).get()).data()!;
    assert.equal(l.agentId, 'agent-wanjiku');
    assert.equal(l.stage, 'new');
    assert.equal(l.consentAt.toDate().getTime(), now.getTime());
    assert.equal(l.retainUntil.toDate().getTime() - now.getTime(), LEAD_RETENTION_DAYS * 86_400_000);
    assert.equal((await db.collection('listings').doc('listing-001').get()).get('stats.leads'), 1);
  });
  test('refuses without consent, without contact, or on a listing that is not live', async () => {
    await rejectsWith(createLead(db, { listingId: 'listing-001', channel: 'form', contact: { phone: '+254700000301' } }), 'invalid-argument');
    await rejectsWith(createLead(db, { listingId: 'listing-001', channel: 'form', contact: {}, consent: true }), 'invalid-argument');
    await rejectsWith(createLead(db, { listingId: 'nope', channel: 'call', contact: { phone: '+254700000301' }, consent: true }), 'not-found');
    await db.collection('listings').doc('listing-002').update({ status: 'draft' });
    await rejectsWith(createLead(db, { listingId: 'listing-002', channel: 'call', contact: { phone: '+254700000301' }, consent: true }), 'not-found');
  });
});

describe('updateLeadStage', () => {
  test('the lead agent moves it along the pipeline; other agents and visitors cannot', async () => {
    assert.deepEqual(await updateLeadStage(db, wanjiku, { leadId: 'lead-001', stage: 'contacted' }), { stage: 'contacted' });
    await rejectsWith(updateLeadStage(db, otieno, { leadId: 'lead-001', stage: 'viewing' }), 'permission-denied');
    await rejectsWith(updateLeadStage(db, visitor, { leadId: 'lead-001', stage: 'viewing' }), 'permission-denied');
    await rejectsWith(updateLeadStage(db, wanjiku, { leadId: 'lead-001', stage: 'new' }), 'failed-precondition');
    await updateLeadStage(db, manager, { leadId: 'lead-001', stage: 'lost' });
  });
});

describe('listings', () => {
  test('an agent submits; it is pending with geohash, unique slug and their agentId', async () => {
    const { listingId, slug } = await submitListing(db, wanjiku, { ...newListing, agentId: 'agent-otieno' }, now);
    const l = (await db.collection('listings').doc(listingId).get()).data()!;
    assert.equal(l.status, 'pending');
    assert.equal(l.agentId, 'agent-wanjiku', 'agents cannot submit as someone else');
    assert.equal(l.geo.geohash.length, 9);
    assert.notEqual(slug, '2-bedroom-apartment-kilimani', 'the seed already uses that slug');
    assert.match(slug, /^2-bedroom-apartment-kilimani-[a-z0-9]{6}$/);
  });
  test('rejects decimals, unknown areas and non-staff', async () => {
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, priceKES: 70000.5 }), 'invalid-argument');
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, area: 'atlantis' }), 'invalid-argument');
    await rejectsWith(submitListing(db, visitor, newListing), 'permission-denied');
  });
  test('a manager approves (live, verified 30 days) or rejects with a reason', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(moderateListing(db, wanjiku, { listingId, action: 'approve' }), 'permission-denied');
    await rejectsWith(moderateListing(db, manager, { listingId, action: 'reject' }), 'invalid-argument');
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    const l = (await db.collection('listings').doc(listingId).get()).data()!;
    assert.equal(l.status, 'live');
    assert.equal(l.expiresAt.toDate().getTime() - l.verifiedAt.toDate().getTime(), 30 * 86_400_000);
    await rejectsWith(moderateListing(db, manager, { listingId, action: 'approve' }), 'failed-precondition');
  });
  test("agents can't edit each other's listings", async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(submitListing(db, otieno, { ...newListing, listingId, priceKES: 1 }), 'permission-denied');
  });
});
