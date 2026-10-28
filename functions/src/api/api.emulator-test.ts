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
import { purgeExpired } from './retention';
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
  for (const c of ['listings', 'leads', 'areas', 'agents', 'viewings', 'audit', 'staff']) {
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
    assert.deepEqual(await purgeExpired(db, now), { leads: 0, viewings: 0 });
  });
});
