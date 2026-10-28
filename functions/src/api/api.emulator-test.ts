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
import { clearLapsedFeatures, confirmListing, expireListings, featureListing, importListings, moderateListing, submitListing } from './listings';
import { bookViewing, rescheduleViewing, updateViewingStatus } from './viewings';
import { addAgentBlock, removeAgentBlock } from './availability';
import { saveAgent } from './agents';
import { monthlyReport } from './reports';
import { checkLimits, LIMITS, WINDOW_MS } from './ratelimit';
import { purgeExpired } from './retention';
import { updateAgentResponseTimes } from './response';
import { dataRequest } from './privacy';
import { bootstrapOwner, setStaffRole, type StaffAuth } from './staff';

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
  for (const c of ['listings', 'leads', 'areas', 'agents', 'viewings', 'audit', 'staff', 'rateLimits']) {
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
  test('each move is in the audit log, refusals are not', async () => {
    await updateLeadStage(db, wanjiku, { leadId: 'lead-001', stage: 'contacted' }, now);
    await rejectsWith(updateLeadStage(db, otieno, { leadId: 'lead-001', stage: 'viewing' }), 'permission-denied');
    const log = (await db.collection('audit').get()).docs.map((d) => d.data());
    assert.equal(log.length, 1);
    assert.deepEqual(
      { ...log[0], at: log[0].at.toDate() },
      { at: now, actor: { uid: 'u1', role: 'agent', agentId: 'agent-wanjiku', name: null }, action: 'lead.stage', target: { collection: 'leads', id: 'lead-001', label: `Lead on ${seedDocs(now).find((d) => d.id === 'listing-001')!.data.title}` }, from: 'new', to: 'contacted' },
    );
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
    const log = (await db.collection('audit').orderBy('action').get()).docs.map((d) => d.data());
    assert.deepEqual(log.map((e) => e.target.label), [newListing.title, newListing.title]);
    assert.deepEqual(log.map((e) => [e.action, e.actor.uid, e.target.id, e.from, e.to]), [
      ['listing.approve', 'm1', listingId, 'pending', 'live'],
      ['listing.submit', 'u1', listingId, null, 'pending'],
    ]);
  });
  test('a rejection never reaches a live listing: resubmitting replaces the document', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await moderateListing(db, manager, { listingId, action: 'reject', reason: 'Blurry photos' }, now);
    assert.equal((await db.collection('listings').doc(listingId).get()).get('rejection.reason'), 'Blurry photos');
    await submitListing(db, wanjiku, { ...newListing, listingId }, now);
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    const l = (await db.collection('listings').doc(listingId).get()).data()!;
    assert.equal(l.status, 'live');
    assert.equal('rejection' in l, false);
  });

  test("media can be reordered or dropped, never borrowed; leaving it out keeps it", async () => {
    const photo = (listingId: string, id: string) => ({
      kind: 'photo',
      variants: { thumb: `media/listings/${listingId}/${id}/thumb.webp`, card: `media/listings/${listingId}/${id}/card.webp`, full: `media/listings/${listingId}/${id}/full.webp` },
      blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
      width: 1600,
      height: 1200,
    });
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    const ref = db.collection('listings').doc(listingId);
    const [a, b] = [photo(listingId, 'aaaa'), photo(listingId, 'bbbb')];
    await ref.update({ media: [a, b] }); // what the media pipeline would have added
    const other = photo('listing-002', 'cccc');
    await db.collection('listings').doc('listing-002').update({ media: [other] });

    // Reorder and drop, sending a trimmed copy: the stored entry is what is kept.
    await submitListing(db, wanjiku, { ...newListing, listingId, media: [{ kind: 'photo', variants: { full: b.variants.full } }] }, now);
    assert.deepEqual((await ref.get()).get('media'), [b]);
    await submitListing(db, wanjiku, { ...newListing, listingId }, now);
    assert.deepEqual((await ref.get()).get('media'), [b], 'no media in the edit keeps what is there');

    await rejectsWith(submitListing(db, wanjiku, { ...newListing, listingId, media: [b, other] }, now), 'invalid-argument');
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, listingId, media: [b, b] }, now), 'invalid-argument');
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, media: [other] }, now), 'invalid-argument');
    assert.deepEqual((await ref.get()).get('media'), [b]);
  });

  test("agents can't edit each other's listings", async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(submitListing(db, otieno, { ...newListing, listingId, priceKES: 1 }), 'permission-denied');
  });
});

/** In-memory accounts, standing in for firebase-admin's Auth. */
class FakeAuth implements StaffAuth {
  users = new Map<string, { uid: string; email: string; displayName?: string; customClaims?: Record<string, unknown> }>();
  add(uid: string, email: string, customClaims?: Record<string, unknown>) {
    this.users.set(email, { uid, email, displayName: uid, customClaims });
  }
  async getUserByEmail(email: string) {
    const u = this.users.get(email);
    if (!u) throw Object.assign(new Error('no user'), { code: 'auth/user-not-found' });
    return u;
  }
  async setCustomUserClaims(uid: string, claims: Record<string, unknown> | null) {
    for (const u of this.users.values()) if (u.uid === uid) u.customClaims = claims ?? undefined;
  }
  claims(email: string) {
    return this.users.get(email)?.customClaims;
  }
}

describe('staff roles', () => {
  const owner: Caller = { uid: 'o1', role: 'owner', agentId: null, name: 'Owner One' };

  test('the first owner comes from the bootstrap script, once', async () => {
    const auth = new FakeAuth();
    auth.add('o1', 'owner@example.com');
    auth.add('o2', 'other@example.com');
    await rejectsWith(bootstrapOwner(db, auth, 'nobody@example.com', now), 'not-found');
    assert.deepEqual(await bootstrapOwner(db, auth, 'owner@example.com', now), { uid: 'o1' });
    assert.deepEqual(auth.claims('owner@example.com'), { role: 'owner' });
    await rejectsWith(bootstrapOwner(db, auth, 'other@example.com', now), 'failed-precondition');
    const entry = (await db.collection('audit').get()).docs[0].data();
    assert.deepEqual([entry.action, entry.actor.name, entry.to], ['staff.role', 'owner bootstrap script', 'owner']);
  });

  test('owners give, change and take away roles; claims, staff list and audit agree', async () => {
    const auth = new FakeAuth();
    auth.add('o1', 'owner@example.com', { role: 'owner' });
    auth.add('u9', 'new@example.com', { beta: true });
    await setStaffRole(db, auth, owner, { email: 'new@example.com', role: 'agent', agentId: 'agent-wanjiku' }, now);
    assert.deepEqual(auth.claims('new@example.com'), { beta: true, role: 'agent', agentId: 'agent-wanjiku' });
    const s = (await db.collection('staff').doc('u9').get()).data()!;
    assert.deepEqual([s.email, s.role, s.agentId], ['new@example.com', 'agent', 'agent-wanjiku']);

    await setStaffRole(db, auth, owner, { email: 'new@example.com', role: 'manager' }, now);
    assert.deepEqual(auth.claims('new@example.com'), { beta: true, role: 'manager' });
    await setStaffRole(db, auth, owner, { email: 'new@example.com', role: null }, now);
    assert.deepEqual(auth.claims('new@example.com'), { beta: true });
    assert.equal((await db.collection('staff').doc('u9').get()).exists, false);

    const entries = (await db.collection('audit').get()).docs.map((d) => d.data());
    assert.deepEqual([...new Set(entries.map((e) => e.target.label))], ['new@example.com']);
    const log = entries.map((e) => `${e.from}->${e.to}`).sort();
    assert.deepEqual(log, ['agent->manager', 'manager->none', 'null->agent']);
  });

  test('only owners; no lock-out; agents need a real agent record; unknown emails refused', async () => {
    const auth = new FakeAuth();
    auth.add('o1', 'owner@example.com', { role: 'owner' });
    auth.add('u9', 'new@example.com');
    await rejectsWith(setStaffRole(db, auth, manager, { email: 'new@example.com', role: 'manager' }), 'permission-denied');
    await rejectsWith(setStaffRole(db, auth, wanjiku, { email: 'new@example.com', role: 'owner' }), 'permission-denied');
    await rejectsWith(setStaffRole(db, auth, owner, { email: 'owner@example.com', role: 'manager' }), 'failed-precondition');
    await rejectsWith(setStaffRole(db, auth, owner, { email: 'new@example.com', role: 'agent' }), 'invalid-argument');
    await rejectsWith(setStaffRole(db, auth, owner, { email: 'new@example.com', role: 'agent', agentId: 'agent-ghost' }), 'invalid-argument');
    await rejectsWith(setStaffRole(db, auth, owner, { email: 'nobody@example.com', role: 'manager' }), 'not-found');
    assert.equal(auth.claims('new@example.com'), undefined);
    assert.equal((await db.collection('audit').get()).size, 0);
  });
});

describe('rate limits (P6-s05)', () => {
  const ask = (phone: string, listingId = 'listing-001') =>
    createLead(db, { listingId, channel: 'form', contact: { phone }, consent: true }, now);
  const leadCount = async () => (await db.collection('leads').count().get()).data().count;

  test('one phone gets a few enquiries an hour; more are refused and store nothing', async () => {
    for (let i = 0; i < LIMITS.leadPerContact; i++) await ask('+254700000501', i % 2 ? 'listing-001' : 'listing-002');
    const before = await leadCount();
    await rejectsWith(ask('+254700000501', 'listing-003'), 'resource-exhausted');
    assert.equal(await leadCount(), before);
    await ask('+254700000502'); // someone else is fine
    // The next hour the same phone may ask again.
    await createLead(db, { listingId: 'listing-001', channel: 'form', contact: { phone: '+254700000501' }, consent: true }, new Date(now.getTime() + WINDOW_MS));
  });

  test('a listing takes a capped number of enquiries an hour, whatever the phones', async () => {
    for (let i = 0; i < LIMITS.leadPerListing; i++) await ask(`+2547000006${String(i).padStart(2, '0')}`);
    await rejectsWith(ask('+254700000699'), 'resource-exhausted');
    await ask('+254700000699', 'listing-002');
  });

  test('viewings are limited per phone too', async () => {
    const client = { name: 'Amina', phone: '+254700000701' };
    const slots = ['10:00', '10:30', '11:00', '11:30'].map((t) => `2026-10-26T${t}:00+03:00`);
    for (const slot of slots.slice(0, LIMITS.viewingPerPhone)) await bookViewing(db, { listingId: 'listing-001', slot, client, consent: true }, now);
    await rejectsWith(bookViewing(db, { listingId: 'listing-001', slot: slots[3], client, consent: true }, now), 'resource-exhausted');
    assert.equal((await db.collection('viewings').count().get()).data().count, LIMITS.viewingPerPhone);
  });

  test('counters hold only a count, under a hashed id, with an expiry', async () => {
    await ask('+254700000801');
    const docs = (await db.collection('rateLimits').get()).docs;
    assert.equal(docs.length, 2); // this phone + the listing
    for (const d of docs) {
      assert.match(d.id, /^[0-9a-f]{64}$/);
      assert.deepEqual(Object.keys(d.data()).sort(), ['count', 'expiresAt', 'window']);
      assert.ok(!JSON.stringify(d.data()).includes('700000801'));
    }
  });

  test('taps are capped per listing', async () => {
    const limits = [{ key: 'tap:listing:test', max: 2 }];
    for (let i = 0; i < 2; i++) await db.runTransaction(async (tx) => (await checkLimits(tx, db, limits, now))());
    await rejectsWith(db.runTransaction(async (tx) => (await checkLimits(tx, db, limits, now))()), 'resource-exhausted');
    await logContactTap(db, { listingId: 'listing-001', channel: 'whatsapp' }, now);
  });
});

describe('retention (D12)', () => {
  const day = 86_400_000;
  const slot = '2026-10-26T10:30:00+03:00';

  test('deletes leads and viewings once retention has passed, and not a day before', async () => {
    const seededLeads = (await db.collection('leads').count().get()).data().count;
    const { viewingId, leadId } = await bookViewing(db, { listingId: 'listing-001', slot, client: { name: 'Amina', phone: '+254700000401' }, consent: true }, now);

    // A day before the lead's retainUntil nothing new goes.
    const retainUntil = (await db.collection('leads').doc(leadId).get()).get('retainUntil').toDate() as Date;
    const early = await purgeExpired(db, new Date(retainUntil.getTime() - day), 2);
    assert.equal((await db.collection('leads').doc(leadId).get()).exists, true);
    assert.equal(early.viewings, 0);

    // Past the viewing slot's retention both are gone, in pages smaller than the set.
    const late = await purgeExpired(db, new Date(new Date(slot).getTime() + LEAD_RETENTION_DAYS * day), 2);
    assert.equal((await db.collection('leads').doc(leadId).get()).exists, false);
    assert.equal((await db.collection('viewings').doc(viewingId).get()).exists, false);
    assert.equal(late.viewings, 1);
    // Seeded leads (retained 365 days from the seed date) went too, so the count is what was there.
    assert.equal(early.leads + late.leads, seededLeads + 1);
    assert.equal((await db.collection('leads').count().get()).data().count, 0);
  });

  test('does nothing while everything is within retention', async () => {
    assert.deepEqual(await purgeExpired(db, now), { leads: 0, viewings: 0, blocks: 0 });
  });
});

describe('verification (P6-s02)', () => {
  const day = 86_400_000;

  test('a live listing not confirmed for 30 days expires overnight; its agent confirms it back to live', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    const ref = db.collection('listings').doc(listingId);

    await expireListings(db, new Date(now.getTime() + 29 * day)); // seeded listings may go; this one is in date
    assert.equal((await ref.get()).get('status'), 'live');
    const later = new Date(now.getTime() + 31 * day);
    const moved = await expireListings(db, later, 2);
    assert.ok(moved >= 1);
    assert.equal((await ref.get()).get('status'), 'expired');
    const entry = (await db.collection('audit').where('action', '==', 'listing.expire').get()).docs.map((d) => d.data()).find((e) => e.target.id === listingId)!;
    assert.deepEqual([entry.actor.name, entry.actor.role, entry.from, entry.to], ['Nightly expiry', null, 'live', 'expired']);

    await rejectsWith(confirmListing(db, otieno, { listingId }, later), 'permission-denied');
    const r = await confirmListing(db, wanjiku, { listingId }, later);
    const l = (await ref.get()).data()!;
    assert.equal(l.status, 'live');
    assert.equal(l.verifiedAt.toDate().getTime(), later.getTime());
    assert.equal(l.expiresAt.toDate().toISOString(), r.expiresAt);
    assert.equal(new Date(r.expiresAt).getTime() - later.getTime(), 30 * day);
    await expireListings(db, new Date(later.getTime() + day));
    assert.equal((await ref.get()).get('status'), 'live', 'confirmed again: in date for 30 more days');
  });

  test('only live or expired listings can be confirmed; visitors cannot', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now); // pending
    await rejectsWith(confirmListing(db, wanjiku, { listingId }, now), 'failed-precondition');
    await rejectsWith(confirmListing(db, visitor, { listingId }, now), 'permission-denied');
    await rejectsWith(confirmListing(db, manager, { listingId: 'no-such' }, now), 'not-found');
  });
});

describe('data requests (DPA 2019, P6-s04)', () => {
  const slot = '2026-10-26T10:30:00+03:00';
  const amina = { name: 'Amina', phone: '+254700000901' };

  async function aminaAsked() {
    await createLead(db, { listingId: 'listing-001', channel: 'form', contact: { phone: amina.phone, email: 'Amina@Example.com' }, message: 'Is it furnished?', consent: true }, now);
    await createLead(db, { listingId: 'listing-002', channel: 'form', contact: { email: 'amina@example.com' }, consent: true }, now);
    await bookViewing(db, { listingId: 'listing-003', slot, client: amina, consent: true }, now);
    await createLead(db, { listingId: 'listing-001', channel: 'form', contact: { phone: '+254700000902' }, consent: true }, now); // someone else
  }

  test('export finds a person by phone or email, as plain JSON, and is audited without their details', async () => {
    await aminaAsked();
    const byPhone = await dataRequest(db, manager, { kind: 'export', phone: amina.phone }, now);
    assert.equal(byPhone.kind, 'export');
    if (byPhone.kind !== 'export') return;
    assert.equal(byPhone.data.leads.length, 2); // her form lead and the viewing's lead
    assert.equal(byPhone.data.viewings.length, 1);
    assert.equal(typeof byPhone.data.leads[0].consentAt, 'string');
    JSON.parse(JSON.stringify(byPhone.data));

    const byEmail = await dataRequest(db, manager, { kind: 'export', email: 'amina@example.com' }, now);
    if (byEmail.kind !== 'export') return assert.fail();
    assert.equal(byEmail.data.leads.length, 2); // stored as typed and lowercased

    const log = (await db.collection('audit').where('action', '==', 'privacy.export').get()).docs.map((d) => d.data());
    assert.equal(log.length, 2);
    assert.ok(!JSON.stringify(log).includes('700000901') && !JSON.stringify(log).toLowerCase().includes('amina'));
  });

  test('delete removes everything held about the person and nothing else', async () => {
    await aminaAsked();
    const before = (await db.collection('leads').count().get()).data().count;
    const r = await dataRequest(db, manager, { kind: 'delete', phone: amina.phone }, now);
    assert.deepEqual(r, { kind: 'delete', deleted: { leads: 2, viewings: 1 } });
    const r2 = await dataRequest(db, manager, { kind: 'delete', email: 'amina@example.com' }, now);
    assert.deepEqual(r2, { kind: 'delete', deleted: { leads: 1, viewings: 0 } });
    assert.equal((await db.collection('leads').count().get()).data().count, before - 3);
    assert.equal((await db.collection('leads').where('contact.phone', '==', '+254700000902').get()).size, 1);
    const entry = (await db.collection('audit').where('action', '==', 'privacy.delete').get()).docs.map((d) => d.data().target.label);
    assert.deepEqual(entry.sort(), ['1 leads, 0 viewings', '2 leads, 1 viewings']);
  });

  test('owners and managers only; needs a phone or an email', async () => {
    await rejectsWith(dataRequest(db, wanjiku, { kind: 'export', phone: amina.phone }, now), 'permission-denied');
    await rejectsWith(dataRequest(db, visitor, { kind: 'delete', phone: amina.phone }, now), 'permission-denied');
    await rejectsWith(dataRequest(db, manager, { kind: 'delete' }, now), 'invalid-argument');
    await rejectsWith(dataRequest(db, manager, { kind: 'export', phone: '0712345678' }, now), 'invalid-argument');
  });
});

describe('response times (P5-s03)', () => {
  const min = 60_000;
  const ask = (i: number) =>
    createLead(db, { listingId: 'listing-001', channel: 'form', contact: { phone: `+2547000011${String(i).padStart(2, '0')}` }, consent: true }, now);

  test("a lead's first move from new records the reply time; later moves keep it", async () => {
    const { leadId } = await ask(0);
    await updateLeadStage(db, wanjiku, { leadId, stage: 'contacted' }, new Date(now.getTime() + 42 * min));
    await updateLeadStage(db, wanjiku, { leadId, stage: 'viewing' }, new Date(now.getTime() + 300 * min));
    const l = (await db.collection('leads').doc(leadId).get()).data()!;
    assert.equal(l.responseMins, 42);
    assert.equal(l.firstResponseAt.toDate().getTime(), now.getTime() + 42 * min);
  });

  test("each agent's typical reply is the median of recent replies, once there are 3", async () => {
    const replies = [5, 30, 600];
    for (const [i, m] of replies.entries()) {
      const { leadId } = await ask(i + 1);
      await updateLeadStage(db, wanjiku, { leadId, stage: i === 2 ? 'lost' : 'contacted' }, new Date(now.getTime() + m * min));
    }
    const day = new Date(now.getTime() + 86_400_000);
    let out = await updateAgentResponseTimes(db, day);
    assert.equal(out['agent-wanjiku'], 30);
    assert.equal((await db.collection('agents').doc('agent-wanjiku').get()).get('responseMins'), 30);
    assert.equal(out['agent-otieno'], null, 'no replies yet: nothing said');

    // Ninety days on, those replies are too old to count.
    out = await updateAgentResponseTimes(db, new Date(now.getTime() + 91 * 86_400_000));
    assert.equal(out['agent-wanjiku'], null);
  });
});

describe('featuring and CSV import (P5-s02)', () => {
  const day = 86_400_000;

  test('a manager features a live listing for some days; it lapses overnight; 0 stops it', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(featureListing(db, manager, { listingId, days: 7 }, now), 'failed-precondition'); // still pending
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    await rejectsWith(featureListing(db, wanjiku, { listingId, days: 7 }, now), 'permission-denied');
    await rejectsWith(featureListing(db, manager, { listingId, days: 91 }, now), 'invalid-argument');

    const r = await featureListing(db, manager, { listingId, days: 7 }, now);
    const ref = db.collection('listings').doc(listingId);
    assert.equal((await ref.get()).get('featuredUntil').toDate().toISOString(), r.featuredUntil);
    const entry = (await db.collection('audit').where('action', '==', 'listing.feature').get()).docs[0].data();
    assert.deepEqual([entry.from, entry.to], ['none', new Date(now.getTime() + 7 * day).toISOString().slice(0, 10)]);

    await clearLapsedFeatures(db, new Date(now.getTime() + 6 * day)); // seeded features may lapse; this one is in date
    assert.notEqual((await ref.get()).get('featuredUntil'), null);
    assert.ok((await clearLapsedFeatures(db, new Date(now.getTime() + 8 * day))) >= 1);
    assert.equal((await ref.get()).get('featuredUntil'), null);

    await featureListing(db, manager, { listingId, days: 3 }, now);
    assert.deepEqual(await featureListing(db, manager, { listingId, days: 0 }, now), { featuredUntil: null });
  });

  test('import makes pending listings row by row; bad rows are reported, the rest go in', async () => {
    const before = (await db.collection('listings').count().get()).data().count;
    const r = await importListings(db, manager, {
      rows: [
        { ...newListing, agentId: 'agent-otieno', title: 'Bedsitter, Kilimani', type: 'bedsitter', beds: 0, priceKES: 15000 },
        { ...newListing, agentId: 'agent-ghost' },
        { ...newListing, agentId: 'agent-wanjiku', priceKES: 70000.5 },
        { ...newListing, agentId: 'agent-wanjiku', listingId: 'listing-001' },
        { ...newListing, agentId: 'agent-wanjiku', title: '3 bedroom house, Kilimani', type: 'bungalow', beds: 3 },
      ],
    }, now);
    assert.deepEqual(r.created.map((c) => c.row), [1, 5]);
    assert.deepEqual(r.failed.map((f) => f.row), [2, 3, 4]);
    assert.match(r.failed[0].error, /no agent "agent-ghost"/);
    assert.match(r.failed[1].error, /priceKES/);
    assert.equal((await db.collection('listings').count().get()).data().count, before + 2);
    const made = (await db.collection('listings').doc(r.created[0].listingId).get()).data()!;
    assert.deepEqual([made.status, made.agentId, made.type], ['pending', 'agent-otieno', 'bedsitter']);

    await rejectsWith(importListings(db, wanjiku, { rows: [newListing] }, now), 'permission-denied');
    await rejectsWith(importListings(db, manager, { rows: [] }, now), 'invalid-argument');
  });
});

describe('viewing status (P5-s05)', () => {
  const slot = '2026-10-26T10:30:00+03:00';
  const after = new Date('2026-10-26T09:00:00Z'); // 12:00 Nairobi, after the 10:30 viewing

  test('the agent confirms, then marks done after the time; the audit names the listing and time, not the client', async () => {
    const { viewingId } = await bookViewing(db, { listingId: 'listing-001', slot, client: { name: 'Amina', phone: '+254700001201' }, consent: true }, now);
    await rejectsWith(updateViewingStatus(db, otieno, { viewingId, status: 'confirmed' }, now), 'permission-denied');
    await rejectsWith(updateViewingStatus(db, wanjiku, { viewingId, status: 'done' }, now), 'failed-precondition'); // not confirmed yet
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'confirmed' }, now);
    await rejectsWith(updateViewingStatus(db, wanjiku, { viewingId, status: 'done' }, now), 'failed-precondition'); // before 10:30
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'no-show' }, after);
    assert.equal((await db.collection('viewings').doc(viewingId).get()).get('status'), 'no-show');
    await rejectsWith(updateViewingStatus(db, manager, { viewingId, status: 'cancelled' }, after), 'failed-precondition'); // final

    const log = (await db.collection('audit').where('action', '==', 'viewing.status').get()).docs.map((d) => d.data());
    assert.deepEqual(log.map((e) => `${e.from}->${e.to}`).sort(), ['confirmed->no-show', 'requested->confirmed']);
    assert.match(log[0].target.label, /^Viewing of .+, 26 Oct,? 10:30$/);
    assert.ok(!JSON.stringify(log).includes('Amina') && !JSON.stringify(log).includes('700001201'));
  });

  test('a cancelled slot can be booked again', async () => {
    const client = { name: 'Juma', phone: '+254700001202' };
    const { viewingId } = await bookViewing(db, { listingId: 'listing-001', slot, client, consent: true }, now);
    await updateViewingStatus(db, manager, { viewingId, status: 'cancelled' }, now);
    const again = await bookViewing(db, { listingId: 'listing-001', slot, client: { name: 'Wairimu', phone: '+254700001203' }, consent: true }, now);
    assert.equal(again.viewingId, viewingId);
    assert.equal((await db.collection('viewings').doc(viewingId).get()).get('status'), 'requested');
  });

  test('the agent moves a viewing to an agreed time: a confirmed one there, the old one cancelled; clashes refused', async () => {
    const client = { name: 'Achieng', phone: '+254700001204' };
    const first = await bookViewing(db, { listingId: 'listing-001', slot, client, consent: true }, now);
    const other = await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-27T11:00:00+03:00', client: { name: 'Otieno', phone: '+254700001205' }, consent: true }, now);
    const to = '2026-10-27T15:00:00+03:00';

    await rejectsWith(rescheduleViewing(db, otieno, { viewingId: first.viewingId, slot: to }, now), 'permission-denied');
    await rejectsWith(rescheduleViewing(db, wanjiku, { viewingId: first.viewingId, slot: '2026-10-25T15:00:00+03:00' }, now), 'invalid-argument'); // Sunday
    await rejectsWith(rescheduleViewing(db, wanjiku, { viewingId: first.viewingId, slot: '2026-10-27T11:00:00+03:00' }, now), 'already-exists');

    const { viewingId } = await rescheduleViewing(db, wanjiku, { viewingId: first.viewingId, slot: to }, now);
    const moved = (await db.collection('viewings').doc(viewingId).get()).data()!;
    const old = (await db.collection('viewings').doc(first.viewingId).get()).data()!;
    assert.deepEqual([moved.status, moved.client.name, moved.rescheduledFrom, moved.slot.toDate().toISOString()], ['confirmed', 'Achieng', first.viewingId, '2026-10-27T12:00:00.000Z']);
    assert.deepEqual([old.status, old.rescheduledTo], ['cancelled', viewingId]);
    await rejectsWith(rescheduleViewing(db, wanjiku, { viewingId: first.viewingId, slot: '2026-10-28T09:00:00+03:00' }, now), 'failed-precondition'); // cancelled

    const log = (await db.collection('audit').where('action', '==', 'viewing.reschedule').get()).docs.map((d) => d.data());
    assert.equal(log.length, 1);
    assert.match(`${log[0].from} -> ${log[0].to}`, /26 Oct,? 10:30 -> 27 Oct,? 15:00/);
    assert.ok(!JSON.stringify(log).includes('Achieng'));
    await updateViewingStatus(db, manager, { viewingId: other.viewingId, status: 'cancelled' }, now);
  });
});


describe('agent time off (P5-s05)', () => {
  test('an agent blocks out time: no viewing can be booked or moved into it; removing it frees the time', async () => {
    const block = await addAgentBlock(db, wanjiku, { start: '2026-10-28T08:00:00+03:00', end: '2026-10-28T13:00:00+03:00', note: 'Site visit in Thika' }, now);
    const client = { name: 'Kamau', phone: '+254700001301' };
    await rejectsWith(bookViewing(db, { listingId: 'listing-001', slot: '2026-10-28T12:30:00+03:00', client, consent: true }, now), 'already-exists');
    await rejectsWith(bookViewing(db, { listingId: 'listing-001', slot: '2026-10-28T07:30:00+03:00', client, consent: true }, now), 'invalid-argument'); // before 8:00 anyway
    const ok = await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-28T13:00:00+03:00', client, consent: true }, now); // ends at 13:00
    await rejectsWith(rescheduleViewing(db, wanjiku, { viewingId: ok.viewingId, slot: '2026-10-28T09:00:00+03:00' }, now), 'already-exists');

    await rejectsWith(removeAgentBlock(db, otieno, block, now), 'permission-denied');
    await removeAgentBlock(db, wanjiku, block, now);
    await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-28T12:30:00+03:00', client: { name: 'Njeri', phone: '+254700001302' }, consent: true }, now);

    const log = (await db.collection('audit').where('action', 'in', ['agent.block', 'agent.unblock']).get()).docs.map((d) => d.data());
    assert.equal(log.length, 2);
    assert.ok(!JSON.stringify(log).includes('Thika'), 'the note stays off the audit log');
  });

  test('managers block for any agent; agents only for themselves; bad ranges refused', async () => {
    const r = await addAgentBlock(db, manager, { agentId: 'agent-otieno', start: '2026-10-30T00:00:00+03:00', end: '2026-10-31T00:00:00+03:00' }, now);
    assert.equal((await db.collection('agentBlocks').doc(r.blockId).get()).get('agentId'), 'agent-otieno');
    const mine = await addAgentBlock(db, wanjiku, { agentId: 'agent-otieno', start: '2026-10-30T00:00:00+03:00', end: '2026-10-30T12:00:00+03:00' }, now);
    assert.equal((await db.collection('agentBlocks').doc(mine.blockId).get()).get('agentId'), 'agent-wanjiku', 'an agent cannot block for someone else');
    await rejectsWith(addAgentBlock(db, wanjiku, { start: '2026-10-30T12:00:00+03:00', end: '2026-10-30T08:00:00+03:00' }, now), 'invalid-argument');
    await rejectsWith(addAgentBlock(db, wanjiku, { start: '2026-10-20T08:00:00+03:00', end: '2026-10-21T08:00:00+03:00' }, now), 'invalid-argument'); // past
    await rejectsWith(addAgentBlock(db, wanjiku, { start: '2026-10-25T08:00:00+03:00', end: '2026-12-25T08:00:00+03:00' }, now), 'invalid-argument'); // > 31 days
    await rejectsWith(addAgentBlock(db, manager, { start: '2026-10-30T08:00:00+03:00', end: '2026-10-30T09:00:00+03:00' }, now), 'invalid-argument'); // no agent
  });
});

describe('agent profiles (P5-s04)', () => {
  const profile = { name: 'Mercy Wambui', earbNo: 'EARB/2026/0412', phone: '+254711000111', whatsapp: '+254711000111', languages: ['en', 'sw'], active: true };

  test('managers add an agent (id from the name, a number on a clash) and edit them; agents cannot', async () => {
    await rejectsWith(saveAgent(db, wanjiku, profile, now), 'permission-denied');
    const a = await saveAgent(db, manager, profile, now);
    assert.equal(a.agentId, 'agent-mercy-wambui');
    const b = await saveAgent(db, manager, { ...profile, phone: '+254711000222', whatsapp: '+254711000222' }, now);
    assert.equal(b.agentId, 'agent-mercy-wambui-2');
    const made = (await db.collection('agents').doc(a.agentId).get()).data()!;
    assert.deepEqual([made.earbNo, made.rating, made.responseMins, made.active], ['EARB/2026/0412', null, null, true]);

    await saveAgent(db, manager, { ...profile, agentId: a.agentId, languages: ['sw'], active: false }, now);
    const edited = (await db.collection('agents').doc(a.agentId).get()).data()!;
    assert.deepEqual([edited.languages, edited.active, edited.rating], [['sw'], false, null]);
    await rejectsWith(saveAgent(db, manager, { ...profile, agentId: 'agent-ghost' }, now), 'not-found');
    await rejectsWith(saveAgent(db, manager, { ...profile, phone: '0711000111' }, now), 'invalid-argument');

    const log = (await db.collection('audit').where('action', '==', 'agent.save').get()).docs.map((d) => `${d.get('from')}->${d.get('to')}`);
    assert.deepEqual(log.sort(), ['active->inactive', 'none->active', 'none->active']);
  });
});

describe('monthly report (P5-s08)', () => {
  test('counts the month by channel, stage and status, per agent; managers only; no client details', async () => {
    const r1 = await createLead(db, { listingId: 'listing-001', channel: 'form', contact: { name: 'Report Client', phone: '+254700001401' }, consent: true }, now);
    await updateLeadStage(db, wanjiku, { leadId: r1.leadId, stage: 'contacted' }, new Date(now.getTime() + 20 * 60_000));
    await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-29T10:00:00+03:00', client: { name: 'Report Client', phone: '+254700001401' }, consent: true }, now);

    await rejectsWith(monthlyReport(db, wanjiku, { month: '2026-10' }), 'permission-denied');
    await rejectsWith(monthlyReport(db, manager, { month: '2026-13' }), 'invalid-argument');
    const r = await monthlyReport(db, manager, { month: '2026-10' });
    assert.ok(r.leads.total >= 2);
    assert.ok(r.leads.byChannel.form >= 1 && r.leads.byChannel.viewing >= 1);
    assert.ok(r.leads.byStage.contacted >= 1);
    assert.ok((r.viewings.byStatus.requested ?? 0) >= 1);
    const w = r.agents.find((a) => a.agentId === 'agent-wanjiku')!;
    assert.ok(w.leads >= 2 && w.name.length > 0);
    assert.equal(typeof w.replyMins, 'number');
    assert.ok(!JSON.stringify(r).includes('Report Client') && !JSON.stringify(r).includes('700001401'));
    assert.equal((await monthlyReport(db, manager, { month: '2025-01' })).leads.total, 0);
  });
});
