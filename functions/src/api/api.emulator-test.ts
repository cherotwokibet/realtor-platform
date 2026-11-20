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
import { clearLapsedFeatures, confirmListing, expireListings, featureListing, importListings, moderateEdit, moderateListing, setHotListing, setPlacement, submitListing } from './listings';
import { bookViewing, openSlots, rescheduleViewing, updateViewingStatus } from './viewings';
import { addAgentBlock, removeAgentBlock } from './availability';
import { saveAgent } from './agents';
import { monthlyReport } from './reports';
import { saveProject } from './projects';
import { logRecommendation, nairobiDay } from './recommendations';
import { MIN_RENTALS, refreshAreaStats, saveArea } from './areas';
import { moderateReview, submitListingReview, submitReview } from './reviews';
import { type PushMessage, type PushSender, sweepSavedSearches } from './alerts';
import { savePage } from './pages';
import { checkLimits, LIMITS, WINDOW_MS } from './ratelimit';
import { purgeExpired } from './retention';
import { updateAgentResponseTimes } from './response';
import { dataRequest } from './privacy';
import { deleteAccount, saveProfile, type CustomerAuth } from './profile';
import { bootstrapOwner, saveStaffProfile, setStaffRole, type StaffAuth } from './staff';

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
  for (const c of ['listings', 'leads', 'areas', 'agents', 'viewings', 'audit', 'staff', 'rateLimits', 'config']) {
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

  test("the listing's viewing fee applies only while M-Pesa is on (P6-s01)", async () => {
    await db.collection('listings').doc('listing-001').update({ viewingFeeKES: 500 });
    const off = await bookViewing(db, { listingId: 'listing-001', slot, client: amina, consent: true }, now);
    assert.equal(off.feeKES, 0, 'no config/tenant: M-Pesa is off');
    assert.equal((await db.collection('viewings').doc(off.viewingId).get()).get('feeKES'), 0);
    await db.collection('config').doc('tenant').set({ features: { mpesa: true } });
    const later = '2026-10-26T11:00:00+03:00';
    const on = await bookViewing(db, { listingId: 'listing-001', slot: later, client: { name: 'Juma', phone: '+254700000402' }, consent: true }, now);
    assert.equal(on.feeKES, 500);
    assert.equal((await db.collection('viewings').doc(on.viewingId).get()).get('feeKES'), 500);
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
  test('the description is stored trimmed, and an over-long one refused (P7-s02)', async () => {
    const { listingId } = await submitListing(db, wanjiku, { ...newListing, description: '  Near Yaya Centre.  ' }, now);
    assert.equal((await db.collection('listings').doc(listingId).get()).get('description'), 'Near Yaya Centre.');
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, description: 'x'.repeat(3001) }, now), 'invalid-argument');
  });
  test("a purpose the tenant switched off is refused at submit and at approval", async () => {
    const short = { ...newListing, purpose: 'short-stay' };
    const { listingId } = await submitListing(db, wanjiku, short, now);
    await db.collection('config').doc('tenant').set({ features: { rent: true, sale: true, shortStay: false } });
    await rejectsWith(submitListing(db, wanjiku, short, now), 'failed-precondition');
    await rejectsWith(moderateListing(db, manager, { listingId, action: 'approve' }, now), 'failed-precondition');
    assert.equal((await db.collection('listings').doc(listingId).get()).get('status'), 'pending');
    await moderateListing(db, manager, { listingId, action: 'reject', reason: 'short stays are off' }, now);
    await submitListing(db, wanjiku, newListing, now);
  });
  test('a live listing whose purpose is switched off cannot be confirmed again', async () => {
    const { listingId } = await submitListing(db, wanjiku, { ...newListing, purpose: 'short-stay' }, now);
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    await db.collection('config').doc('tenant').set({ features: { shortStay: false } });
    await rejectsWith(confirmListing(db, wanjiku, { listingId }, now), 'failed-precondition');
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
  async updateUser(uid: string, props: { displayName?: string }) {
    for (const u of this.users.values()) if (u.uid === uid && props.displayName) u.displayName = props.displayName;
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

describe('staff profile (Account)', () => {
  test('staff save their own name and phone; others and bad input refused', async () => {
    const auth = new FakeAuth();
    auth.add('u-agent-wanjiku', 'wanjiku@example.com', { role: 'agent', agentId: 'agent-wanjiku' });
    await db.collection('staff').doc('u-agent-wanjiku').set({ email: 'wanjiku@example.com', role: 'agent', agentId: 'agent-wanjiku' });
    const me: Caller = { uid: 'u-agent-wanjiku', role: 'agent', agentId: 'agent-wanjiku' };
    await saveStaffProfile(db, auth, me, { name: 'Wanjiku M.', phone: '+254712345678' }, now);
    const s = (await db.collection('staff').doc('u-agent-wanjiku').get()).data()!;
    assert.deepEqual([s.name, s.phone, s.role], ['Wanjiku M.', '+254712345678', 'agent']);
    assert.equal(auth.users.get('wanjiku@example.com')!.displayName, 'Wanjiku M.');
    await rejectsWith(saveStaffProfile(db, auth, me, { name: 'W', phone: '0712' }), 'invalid-argument');
    await rejectsWith(saveStaffProfile(db, auth, { uid: 'c1', role: null, agentId: null }, { name: 'Customer' }), 'permission-denied');
    await rejectsWith(saveStaffProfile(db, auth, { uid: 'ghost', role: 'manager', agentId: null }, { name: 'Ghost' }), 'failed-precondition');
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
    assert.deepEqual(r, { kind: 'delete', deleted: { leads: 2, viewings: 1, reviews: 0 } });
    const r2 = await dataRequest(db, manager, { kind: 'delete', email: 'amina@example.com' }, now);
    assert.deepEqual(r2, { kind: 'delete', deleted: { leads: 1, viewings: 0, reviews: 0 } });
    assert.equal((await db.collection('leads').count().get()).data().count, before - 3);
    assert.equal((await db.collection('leads').where('contact.phone', '==', '+254700000902').get()).size, 1);
    const entry = (await db.collection('audit').where('action', '==', 'privacy.delete').get()).docs.map((d) => d.data().target.label);
    assert.deepEqual(entry.sort(), ['1 leads, 0 viewings, 0 reviews', '2 leads, 1 viewings, 0 reviews']);
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

  test('a manager puts a live listing in Hot Properties and takes it out; audited', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(setHotListing(db, manager, { listingId, hot: true }, now), 'failed-precondition'); // still pending
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    await rejectsWith(setHotListing(db, wanjiku, { listingId, hot: true }, now), 'permission-denied');
    await rejectsWith(setHotListing(db, manager, { listingId, hot: 'yes' }, now), 'invalid-argument');
    assert.deepEqual(await setHotListing(db, manager, { listingId, hot: true }, now), { hot: true });
    const ref = db.collection('listings').doc(listingId);
    assert.equal((await ref.get()).get('hot'), true);
    const entry = (await db.collection('audit').where('action', '==', 'listing.hot').get()).docs[0].data();
    assert.deepEqual([entry.from, entry.to], ['none', 'hot']);
    await setHotListing(db, manager, { listingId, hot: false }, now);
    assert.equal((await ref.get()).get('hot'), false);
  });

  test('Recommended and pinned-first-in-Newest: managers place live listings; audited', async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(setPlacement(db, manager, { listingId, placement: 'recommended', on: true }, now), 'failed-precondition');
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    await rejectsWith(setPlacement(db, wanjiku, { listingId, placement: 'recommended', on: true }, now), 'permission-denied');
    await rejectsWith(setPlacement(db, manager, { listingId, placement: 'banner', on: true }, now), 'invalid-argument');
    await setPlacement(db, manager, { listingId, placement: 'recommended', on: true }, now);
    await setPlacement(db, manager, { listingId, placement: 'newest', on: true }, now);
    const l = (await db.collection('listings').doc(listingId).get()).data()!;
    assert.deepEqual([l.recommended, l.pinnedNewest], [true, true]);
    const actions = (await db.collection('audit').where('target.id', '==', listingId).get()).docs.map((d) => d.get('action'));
    assert.ok(actions.includes('listing.recommend') && actions.includes('listing.pin-newest'));
  });

  test("an agent's edit to a live listing waits for a manager; the listing stays live and keeps its placements", async () => {
    const { listingId } = await submitListing(db, wanjiku, newListing, now);
    await moderateListing(db, manager, { listingId, action: 'approve' }, now);
    await setPlacement(db, manager, { listingId, placement: 'hot', on: true }, now);
    const ref = db.collection('listings').doc(listingId);

    const r = await submitListing(db, wanjiku, { ...newListing, listingId, priceKES: 75000, estate: 'Riverside' }, now);
    assert.equal(r.editRequest, true);
    assert.deepEqual(r.changed?.sort(), ['estate', 'priceKES']);
    let l = (await ref.get()).data()!;
    assert.deepEqual([l.status, l.priceKES, l.hot], ['live', 70000, true], 'unchanged until approved');
    const edit = (await db.collection('listingEdits').doc(listingId).get()).data()!;
    assert.deepEqual([edit.status, edit.agentId, edit.proposed.priceKES], ['pending', 'agent-wanjiku', 75000]);

    await rejectsWith(moderateEdit(db, wanjiku, { listingId, action: 'approve' }, now), 'permission-denied');
    await rejectsWith(moderateEdit(db, manager, { listingId, action: 'reject' }, now), 'invalid-argument'); // needs a reason
    await moderateEdit(db, manager, { listingId, action: 'approve' }, now);
    l = (await ref.get()).data()!;
    assert.deepEqual([l.status, l.priceKES, l.estate, l.hot], ['live', 75000, 'Riverside', true]);
    await rejectsWith(moderateEdit(db, manager, { listingId, action: 'approve' }, now), 'not-found'); // nothing waiting now

    // A second edit, rejected: the listing is unchanged; the agent sees why.
    await submitListing(db, wanjiku, { ...newListing, listingId, priceKES: 1000 }, now);
    await moderateEdit(db, manager, { listingId, action: 'reject', reason: 'That price looks wrong' }, now);
    assert.equal((await ref.get()).get('priceKES'), 75000);
    assert.deepEqual([(await db.collection('listingEdits').doc(listingId).get()).get('status')], ['rejected']);

    // A manager's own edit applies at once and stays live; leaving out an optional field removes it.
    const m = await submitListing(db, manager, { ...newListing, listingId, agentId: 'agent-wanjiku', priceKES: 80000 }, now);
    assert.equal(m.editRequest, undefined);
    l = (await ref.get()).data()!;
    assert.deepEqual([l.status, l.priceKES, l.estate, l.hot], ['live', 80000, undefined, true]);
    // Not someone else's.
    await rejectsWith(submitListing(db, otieno, { ...newListing, listingId, priceKES: 1 }, now), 'permission-denied');
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

describe('similar-homes click-through (P7-s04)', () => {
  test('counts shown and opened per Nairobi day and surface; the monthly report adds them up; nothing about the visitor', async () => {
    const day = new Date('2026-11-03T22:30:00Z'); // 01:30 on 4 Nov in Nairobi
    assert.equal(nairobiDay(day), '2026-11-04');
    for (const e of [
      { event: 'shown', surface: 'app' },
      { event: 'shown', surface: 'app' },
      { event: 'shown', surface: 'web' },
      { event: 'opened', surface: 'app' },
    ]) {
      await logRecommendation(db, { listingId: 'listing-001', ...e }, day);
    }
    const doc = (await db.collection('stats').doc('recommendations-2026-11-04').get()).data()!;
    assert.deepEqual(doc, { day: '2026-11-04', app: { shown: 2, opened: 1 }, web: { shown: 1 } });
    await rejectsWith(logRecommendation(db, { listingId: 'listing-001', event: 'liked', surface: 'app' }, day), 'invalid-argument');

    await logRecommendation(db, { listingId: 'listing-001', event: 'opened', surface: 'web' }, new Date('2026-12-01T00:00:00Z'));
    const nov = await monthlyReport(db, manager, { month: '2026-11' });
    assert.deepEqual(nov.recommendations, { shown: 3, opened: 1 });
    assert.deepEqual((await monthlyReport(db, manager, { month: '2026-12' })).recommendations, { shown: 0, opened: 1 });
  });
});

describe('area guides (P3-s05)', () => {
  const guide = { name: 'Muthaiga North', county: 'Nairobi', lat: -1.23, lng: 36.84, guide: 'Quiet, leafy, near Runda.', amenities: ['Village Market'] };

  test('managers add and edit an area; agents cannot; stats stay with the nightly job', async () => {
    await rejectsWith(saveArea(db, wanjiku, guide, now), 'permission-denied');
    const { slug } = await saveArea(db, manager, guide, now);
    assert.equal(slug, 'muthaiga-north');
    await rejectsWith(saveArea(db, manager, guide, now), 'already-exists');
    await saveArea(db, manager, { ...guide, slug, guide: 'Updated guide.', amenities: [] }, now);
    const a = (await db.collection('areas').doc(slug).get()).data()!;
    assert.deepEqual([a.guide, a.amenities, a.stats], ['Updated guide.', [], { medianRentKES: null, listings: 0 }]);
    await rejectsWith(saveArea(db, manager, { ...guide, slug: 'nowhere' }, now), 'not-found');
    await rejectsWith(saveArea(db, manager, { ...guide, lat: 51.5, lng: -0.1 }, now), 'invalid-argument');
  });

  test('an area can have an outline (geofence); listings must be pinned inside it', async () => {
    // A box around Kilimani's centre (-1.2921, 36.7856) that the seed listing's pin (-1.2905, 36.786) sits in.
    const box = [
      { lat: -1.28, lng: 36.77 },
      { lat: -1.28, lng: 36.8 },
      { lat: -1.305, lng: 36.8 },
      { lat: -1.305, lng: 36.77 },
    ];
    const kili = (await db.collection('areas').doc('kilimani').get()).data()!;
    const base = { slug: 'kilimani', name: kili.name, county: kili.county, lat: kili.centre.lat, lng: kili.centre.lng, guide: kili.guide ?? '', amenities: kili.amenities ?? [] };
    await rejectsWith(saveArea(db, manager, { ...base, boundary: [box[0], box[2], box[1], box[3]] }, now), 'invalid-argument'); // crossed
    await rejectsWith(saveArea(db, manager, { ...base, boundary: box.map((p) => ({ lat: p.lat + 1, lng: p.lng })) }, now), 'invalid-argument'); // centre outside
    await saveArea(db, manager, { ...base, boundary: box }, now);
    assert.deepEqual((await db.collection('areas').doc('kilimani').get()).get('boundary'), box);

    await submitListing(db, wanjiku, newListing, now);
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, lat: -1.2676, lng: 36.8108 }, now), 'invalid-argument'); // Westlands
    // Extra charges ride along.
    const { listingId } = await submitListing(db, wanjiku, { ...newListing, extraCharges: [{ name: 'Water', amountKES: 500, per: 'month' }] }, now);
    assert.deepEqual((await db.collection('listings').doc(listingId).get()).get('extraCharges'), [{ name: 'Water', amountKES: 500, per: 'month' }]);
    await rejectsWith(submitListing(db, wanjiku, { ...newListing, extraCharges: [{ name: 'X', amountKES: 5, per: 'year' }] }, now), 'invalid-argument');

    // Taking the outline away lifts the check.
    await saveArea(db, manager, { ...base, boundary: null }, now);
    await submitListing(db, wanjiku, { ...newListing, lat: -1.2676, lng: 36.8108 }, now);
  });

  test('nightly stats: live listings per area, median rent once there are enough rentals', async () => {
    await refreshAreaStats(db);
    const areas = await db.collection('areas').get();
    const live = await db.collection('listings').where('status', '==', 'live').get();
    for (const a of areas.docs) {
      const here = live.docs.filter((l) => l.get('area') === a.id);
      const rents = here.filter((l) => l.get('purpose') === 'rent').map((l) => l.get('priceKES') as number).sort((x, y) => x - y);
      assert.equal(a.get('stats.listings'), here.length, a.id);
      if (rents.length < MIN_RENTALS) assert.equal(a.get('stats.medianRentKES'), null, a.id);
      else assert.ok(a.get('stats.medianRentKES') >= rents[0] && a.get('stats.medianRentKES') <= rents.at(-1)!, a.id);
    }
  });
});

describe('open slots (P4-s04)', () => {
  test("a day's free times leave out booked slots and time off; past notice and Sundays give none", async () => {
    const all = await openSlots(db, { listingId: 'listing-001', day: '2026-10-31' }, now);
    assert.equal(all.times.length, 20);
    assert.deepEqual([all.times[0], all.times.at(-1)], ['08:00', '17:30']);

    await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-31T10:00:00+03:00', client: { name: 'Slot Client', phone: '+254700001501' }, consent: true }, now);
    await addAgentBlock(db, wanjiku, { start: '2026-10-31T14:00:00+03:00', end: '2026-10-31T15:15:00+03:00' }, now);
    const free = (await openSlots(db, { listingId: 'listing-001', day: '2026-10-31' }, now)).times;
    assert.ok(!free.includes('10:00'));
    assert.ok(!['14:00', '14:30', '15:00'].some((t) => free.includes(t)));
    assert.ok(free.includes('13:30') && free.includes('15:30'));

    assert.deepEqual((await openSlots(db, { listingId: 'listing-001', day: '2026-10-25' }, now)).times, []); // Sunday
    assert.deepEqual((await openSlots(db, { listingId: 'listing-001', day: '2026-10-20' }, now)).times, []); // past
    await rejectsWith(openSlots(db, { listingId: 'no-such', day: '2026-10-31' }, now), 'not-found');
    await rejectsWith(openSlots(db, { listingId: 'listing-001', day: '31/10/2026' }, now), 'invalid-argument');
  });
});

describe('reviews (P6-s03)', () => {
  test('a done viewing gives one review link; the review waits for a manager; approving sets the rating', async () => {
    // Start from no reviews (other suites may share this emulator).
    for (const d of (await db.collection('reviews').get()).docs) await d.ref.delete();
    const { viewingId } = await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-27T11:30:00+03:00', client: { name: 'Akinyi Otieno', phone: '+254700001601' }, consent: true }, now);
    const later = new Date('2026-10-27T12:00:00Z');
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'confirmed' }, now);
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'done' }, later);
    const token = (await db.collection('viewings').doc(viewingId).get()).get('reviewToken') as string;
    assert.match(token, /^[A-Za-z0-9_-]{24}$/);

    await rejectsWith(submitReview(db, { token: 'x'.repeat(24), rating: 5 }, later), 'not-found');
    await rejectsWith(submitReview(db, { token, rating: 6 }, later), 'invalid-argument');
    const { reviewId } = await submitReview(db, { token, rating: 4, comment: 'On time and honest.', name: 'Akinyi Otieno' }, later);
    await rejectsWith(submitReview(db, { token, rating: 1 }, later), 'already-exists');
    const review = (await db.collection('reviews').doc(reviewId).get()).data()!;
    assert.deepEqual([review.status, review.name, review.agentId], ['pending', 'Akinyi', 'agent-wanjiku']);
    assert.ok(!JSON.stringify(review).includes('700001601'));

    await rejectsWith(moderateReview(db, wanjiku, { reviewId, action: 'approve' }, later), 'permission-denied');
    assert.deepEqual(await moderateReview(db, manager, { reviewId, action: 'approve' }, later), { rating: 4, ratingCount: 1 });
    const agent = (await db.collection('agents').doc('agent-wanjiku').get()).data()!;
    assert.deepEqual([agent.rating, agent.ratingCount], [4, 1]);
    assert.deepEqual(await moderateReview(db, manager, { reviewId, action: 'hide' }, later), { rating: null, ratingCount: 0 });
  });

  test('a review link runs out after 30 days', async () => {
    const { viewingId } = await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-27T12:30:00+03:00', client: { name: 'Baraka', phone: '+254700001602' }, consent: true }, now);
    const later = new Date('2026-10-27T12:00:00Z');
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'confirmed' }, now);
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'done' }, later);
    const token = (await db.collection('viewings').doc(viewingId).get()).get('reviewToken') as string;
    await rejectsWith(submitReview(db, { token, rating: 5 }, new Date('2026-12-01T00:00:00Z')), 'failed-precondition');
  });
});

describe('listing reviews', () => {
  test('a signed-in visitor reviews a home once; it waits for a manager and never moves the agent rating', async () => {
    for (const d of (await db.collection('reviews').get()).docs) await d.ref.delete();
    const visitor = { uid: 'customer-1', role: null, agentId: null };
    const input = { listingId: 'listing-001', rating: 2, comment: 'Lovely flat, but the water is rationed.', name: 'Achieng Atieno' };
    await rejectsWith(submitListingReview(db, { uid: null, role: null, agentId: null }, input, now), 'unauthenticated');
    await rejectsWith(submitListingReview(db, visitor, { ...input, comment: 'ok' }, now), 'invalid-argument');
    await rejectsWith(submitListingReview(db, visitor, { ...input, listingId: 'no-such-listing' }, now), 'failed-precondition');
    const { reviewId } = await submitListingReview(db, visitor, input, now);
    await rejectsWith(submitListingReview(db, visitor, input, now), 'already-exists');
    const review = (await db.collection('reviews').doc(reviewId).get()).data()!;
    assert.deepEqual([review.kind, review.status, review.name, review.listingId, review.agentId], ['listing', 'pending', 'Achieng', 'listing-001', 'agent-wanjiku']);
    assert.ok(!JSON.stringify(review).includes('customer-1') && !reviewId.includes('customer-1'), 'the account id is not stored');
    assert.deepEqual(await moderateReview(db, manager, { reviewId, action: 'approve' }, now), { rating: null, ratingCount: 0 }, 'not counted for the agent');
  });
});

describe('reviews and data requests', () => {
  test("a person's reviews go with their viewings in an export or a delete; the rating follows", async () => {
    for (const d of (await db.collection('reviews').get()).docs) await d.ref.delete();
    const phone = '+254700001701';
    const { viewingId } = await bookViewing(db, { listingId: 'listing-001', slot: '2026-10-27T13:30:00+03:00', client: { name: 'Wangari', phone }, consent: true }, now);
    const later = new Date('2026-10-27T12:00:00Z');
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'confirmed' }, now);
    await updateViewingStatus(db, wanjiku, { viewingId, status: 'done' }, later);
    const token = (await db.collection('viewings').doc(viewingId).get()).get('reviewToken') as string;
    const { reviewId } = await submitReview(db, { token, rating: 5, name: 'Wangari' }, later);
    await moderateReview(db, manager, { reviewId, action: 'approve' }, later);

    const exp = await dataRequest(db, manager, { kind: 'export', phone }, later);
    assert.ok(exp.kind === 'export' && exp.data.reviews.length === 1 && exp.data.reviews[0].name === 'Wangari');
    const del = await dataRequest(db, manager, { kind: 'delete', phone }, later);
    assert.ok(del.kind === 'delete' && del.deleted.reviews === 1);
    assert.equal((await db.collection('reviews').doc(reviewId).get()).exists, false);
    assert.equal((await db.collection('agents').doc('agent-wanjiku').get()).get('ratingCount'), 0);
  });
});

describe('saved-search alerts (D18)', () => {
  test('a listing going live lands once in the inbox of each matching saved search', async () => {
    await db.collection('savedSearches').doc('ss-kili').set({ userId: 'alice', filters: { purpose: 'rent', areas: ['kilimani'], maxPriceKES: 200000 }, channels: ['inbox'], lastNotifiedAt: null, createdAt: now });
    await db.collection('savedSearches').doc('ss-sale').set({ userId: 'bob', filters: { purpose: 'sale' }, channels: ['inbox'], lastNotifiedAt: null, createdAt: now });
    await db.collection('config').doc('alerts').set({ lastSweepAt: new Date(now.getTime() - 60_000) });
    const { listingId } = await submitListing(db, wanjiku, { ...newListing, priceKES: 60000 }, now);
    const at = new Date(now.getTime() + 60_000);
    await moderateListing(db, manager, { listingId, action: 'approve' }, at);

    const r = await sweepSavedSearches(db, new Date(at.getTime() + 1000));
    assert.ok(r.listings >= 1);
    const alice = (await db.collection('users').doc('alice').collection('alerts').get()).docs.map((d) => d.data());
    assert.ok(alice.some((a) => a.listingId === listingId && a.priceKES === 60000 && a.readAt === null));
    const bob = (await db.collection('users').doc('bob').collection('alerts').get()).docs;
    assert.ok(!bob.some((d) => d.get('listingId') === listingId), 'a sale search gets no rental');
    assert.notEqual((await db.collection('savedSearches').doc('ss-kili').get()).get('lastNotifiedAt'), null);

    const again = await sweepSavedSearches(db, new Date(at.getTime() + 3_600_000));
    assert.equal(again.listings, 0, 'the next sweep starts where this one stopped');
  });

  test('phones that turned alerts on get one push per person; dead tokens are forgotten', async () => {
    await db.collection('savedSearches').doc('ss-p1').set({ userId: 'carol', filters: { purpose: 'rent' }, channels: ['inbox'], lastNotifiedAt: null, createdAt: now });
    await db.collection('savedSearches').doc('ss-p2').set({ userId: 'carol', filters: { purpose: 'rent', areas: ['kilimani'] }, channels: ['inbox'], lastNotifiedAt: null, createdAt: now });
    await db.collection('savedSearches').doc('ss-p3').set({ userId: 'dan', filters: { purpose: 'rent' }, channels: ['inbox'], lastNotifiedAt: null, createdAt: now });
    const devices = db.collection('users').doc('carol').collection('devices');
    await devices.doc('tok-live').set({ token: 'tok-live', platform: 'android', updatedAt: now });
    await devices.doc('tok-dead').set({ token: 'tok-dead', platform: 'android', updatedAt: now });
    const start = new Date(now.getTime() + 2 * 3_600_000);
    await db.collection('config').doc('alerts').set({ lastSweepAt: start });
    const { listingId } = await submitListing(db, wanjiku, { ...newListing, priceKES: 70000 }, start);
    const at = new Date(start.getTime() + 60_000);
    await moderateListing(db, manager, { listingId, action: 'approve' }, at);

    const sent: { tokens: string[]; m: PushMessage }[] = [];
    const push: PushSender = { send: async (tokens, m) => (sent.push({ tokens, m }), ['tok-dead']) };
    const r = await sweepSavedSearches(db, new Date(at.getTime() + 1000), push);
    assert.equal(sent.length, 1, 'two matching searches, one push; dan has no phone registered');
    assert.deepEqual([...sent[0].tokens].sort(), ['tok-dead', 'tok-live']);
    assert.equal(sent[0].m.title, 'A new home matches your search');
    assert.match(sent[0].m.path, /^\/listing\//);
    assert.equal(r.pushed, 1);
    assert.deepEqual((await devices.get()).docs.map((d) => d.id), ['tok-live']);

    const failing: PushSender = { send: async () => { throw new Error('FCM down'); } };
    await moderateListing(db, manager, { listingId: (await submitListing(db, wanjiku, newListing, at)).listingId, action: 'approve' }, new Date(at.getTime() + 2000));
    const r2 = await sweepSavedSearches(db, new Date(at.getTime() + 3000), failing);
    assert.ok(r2.alerts >= 1, 'the inbox still gets them when push fails');
  });
});

describe('a customer\'s own profile and account', () => {
  const customer: Caller = { uid: 'cust-9', role: null, agentId: null };
  const calls: string[] = [];
  const auth: CustomerAuth = {
    setName: async (uid, name) => void calls.push(`name ${uid} ${name}`),
    deleteUser: async (uid) => void calls.push(`delete ${uid}`),
  };

  test('saves the name and a checked WhatsApp number; signed out or a bad number is refused', async () => {
    await rejectsWith(saveProfile(db, auth, visitor, { name: 'Amina', whatsapp: '' }, now), 'unauthenticated');
    await rejectsWith(saveProfile(db, auth, customer, { name: 'Amina', whatsapp: '0712345678' }, now), 'invalid-argument');
    assert.deepEqual(await saveProfile(db, auth, customer, { name: ' Amina W ', whatsapp: '+254712345678' }, now), { name: 'Amina W', whatsapp: '+254712345678' });
    const doc = (await db.collection('users').doc('cust-9').get()).data()!;
    assert.equal(doc.whatsapp, '+254712345678');
    assert.ok(calls.includes('name cust-9 Amina W'));
    assert.equal((await saveProfile(db, auth, customer, { name: 'Amina W', whatsapp: '' }, now)).whatsapp, null, 'empty clears it');
  });

  test('deleting the account removes the profile, saved searches, alerts and devices, then the sign-in', async () => {
    const user = db.collection('users').doc('cust-9');
    await user.set({ name: 'Amina' });
    await user.collection('alerts').doc('a1').set({ slug: 'x' });
    await user.collection('devices').doc('t1').set({ token: 't1' });
    await db.collection('savedSearches').doc('s-cust-9').set({ userId: 'cust-9', filters: { purpose: 'rent' } });
    await rejectsWith(deleteAccount(db, auth, manager), 'failed-precondition');
    assert.deepEqual(await deleteAccount(db, auth, customer), { deleted: true });
    assert.equal((await user.get()).exists, false);
    assert.equal((await user.collection('alerts').get()).size, 0);
    assert.equal((await user.collection('devices').get()).size, 0);
    assert.equal((await db.collection('savedSearches').doc('s-cust-9').get()).exists, false);
    assert.ok(calls.includes('delete cust-9'));
  });
});

describe('off-plan projects (P5-s06)', () => {
  const project = {
    name: 'Mvuli Gardens',
    developer: 'Test Developers',
    area: 'kilimani',
    summary: 'Two towers.',
    completion: '2028-03',
    units: [
      { type: 'apartment', beds: 2, sizeSqm: 80, fromKES: 8_500_000, available: 10 },
      { type: 'apartment', beds: 1, fromKES: 5_500_000, available: 4 },
    ],
    paymentPlan: [
      { stage: 'Deposit', percent: 10 },
      { stage: 'Instalments', percent: 70 },
      { stage: 'Handover', percent: 20 },
    ],
    published: false,
  };

  test('managers save and publish a project; agents cannot; the plan must add up; not when switched off', async () => {
    await rejectsWith(saveProject(db, wanjiku, project, now), 'permission-denied');
    const { slug } = await saveProject(db, manager, project, now);
    assert.equal(slug, 'mvuli-gardens');
    await rejectsWith(saveProject(db, manager, project, now), 'already-exists');
    await saveProject(db, manager, { ...project, slug, published: true }, now);
    const p = (await db.collection('projects').doc(slug).get()).data()!;
    assert.deepEqual([p.published, p.fromKES, p.area, 'slug' in p], [true, 5_500_000, 'kilimani', false]);

    await rejectsWith(saveProject(db, manager, { ...project, name: 'Bad Plan', paymentPlan: [{ stage: 'Deposit', percent: 50 }] }, now), 'invalid-argument');
    await rejectsWith(saveProject(db, manager, { ...project, name: 'Nowhere', area: 'atlantis' }, now), 'invalid-argument');
    await rejectsWith(saveProject(db, manager, { ...project, slug: 'no-such-project' }, now), 'not-found');

    const log = (await db.collection('audit').where('action', '==', 'project.save').get()).docs.map((d) => `${d.get('from')}->${d.get('to')}`);
    assert.deepEqual(log.sort(), ['draft->published', 'none->draft']);

    const tenant = db.collection('config').doc('tenant');
    const before = await tenant.get();
    await tenant.set({ features: { offPlan: false } }, { merge: true });
    try {
      await rejectsWith(saveProject(db, manager, { ...project, name: 'Switched Off' }, now), 'failed-precondition');
    } finally {
      if (before.exists) await tenant.set(before.data()!);
      else await tenant.delete();
    }
  });
});

describe('site pages (P5-s07)', () => {
  test('managers save and publish a page; agents cannot; only known pages', async () => {
    await rejectsWith(savePage(db, wanjiku, { slug: 'about', title: 'About us', body: 'Hi', published: true }, now), 'permission-denied');
    await savePage(db, manager, { slug: 'privacy', title: 'Privacy notice', body: '# Who we are\nRealtime.', published: false }, now);
    await savePage(db, manager, { slug: 'privacy', title: 'Privacy notice', body: '# Who we are\nRealtime.', published: true }, now);
    const p = (await db.collection('pages').doc('privacy').get()).data()!;
    assert.deepEqual([p.title, p.published], ['Privacy notice', true]);
    await rejectsWith(savePage(db, manager, { slug: 'secret', title: 'x', body: '', published: true }, now), 'invalid-argument');
    const log = (await db.collection('audit').where('action', '==', 'page.save').get()).docs.map((d) => `${d.get('from')}->${d.get('to')}`);
    assert.deepEqual(log.sort(), ['draft->published', 'none->draft']);
  });
});
