/**
 * Firestore rules tests. Run against the emulator:
 *   firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run test:rules"
 * Every collection in docs/data-model.md has cases for the public, a
 * signed-in user, an agent, a manager and the write paths Functions own.
 */
import { after, before, beforeEach, describe, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, collection, getDocs, query, where } from 'firebase/firestore';
import { seedDocs } from '../seed/data';

let env: RulesTestEnvironment;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-realtor',
    firestore: { rules: readFileSync(join(__dirname, '..', '..', '..', 'firestore.rules'), 'utf8') },
  });
});

after(async () => env?.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const d of seedDocs()) await setDoc(doc(db, d.collection, d.id), d.data);
    await setDoc(doc(db, 'listings', 'draft-1'), { ...seedDocs().find((d) => d.id === 'listing-001')!.data, status: 'draft', agentId: 'agent-otieno' });
    await setDoc(doc(db, 'agents', 'agent-gone'), { name: 'Former Agent', active: false });
    await setDoc(doc(db, 'audit', 'a-1'), { at: new Date(), action: 'lead.stage', actor: { uid: 'boss', role: 'manager', agentId: null } });
    await setDoc(doc(db, 'payments', 'pay-1'), { purpose: 'viewing-fee', amountKES: 500, status: 'paid' });
    await setDoc(doc(db, 'viewings', 'view-1'), { listingId: 'listing-001', agentId: 'agent-wanjiku', status: 'requested' });
    await setDoc(doc(db, 'config', 'tenant'), { id: 'demo' });
    await setDoc(doc(db, 'savedSearches', 'ss-1'), { userId: 'alice', filters: { purpose: 'rent' }, channels: ['push'], lastNotifiedAt: null, createdAt: new Date() });
  });
});

const visitor = () => env.unauthenticatedContext().firestore();
const user = (uid = 'alice') => env.authenticatedContext(uid).firestore();
const agent = (agentId = 'agent-wanjiku') => env.authenticatedContext(`u-${agentId}`, { role: 'agent', agentId }).firestore();
const manager = () => env.authenticatedContext('boss', { role: 'manager' }).firestore();

describe('listings', () => {
  test('anyone reads live listings', async () => {
    await assertSucceeds(getDoc(doc(visitor(), 'listings', 'listing-001')));
  });
  test('a public query must ask for live only', async () => {
    await assertSucceeds(getDocs(query(collection(visitor(), 'listings'), where('status', '==', 'live'))));
    await assertFails(getDocs(collection(visitor(), 'listings')));
  });
  test('drafts: hidden from the public and other agents, visible to their agent and managers', async () => {
    await assertFails(getDoc(doc(visitor(), 'listings', 'draft-1')));
    await assertFails(getDoc(doc(agent('agent-wanjiku'), 'listings', 'draft-1')));
    await assertSucceeds(getDoc(doc(agent('agent-otieno'), 'listings', 'draft-1')));
    await assertSucceeds(getDoc(doc(manager(), 'listings', 'draft-1')));
  });
  test('no client sets status, verification or price, not even a manager', async () => {
    await assertFails(updateDoc(doc(agent('agent-wanjiku'), 'listings', 'listing-001'), { status: 'live' }));
    await assertFails(updateDoc(doc(manager(), 'listings', 'listing-001'), { verifiedAt: new Date() }));
    await assertFails(setDoc(doc(user(), 'listings', 'new'), { title: 'x', status: 'live' }));
  });
});

describe('agents, areas, config', () => {
  test('active agents and areas are public; inactive agents are staff-only', async () => {
    await assertSucceeds(getDoc(doc(visitor(), 'agents', 'agent-wanjiku')));
    await assertFails(getDoc(doc(visitor(), 'agents', 'agent-gone')));
    await assertSucceeds(getDoc(doc(agent(), 'agents', 'agent-gone')));
    await assertSucceeds(getDoc(doc(visitor(), 'areas', 'kilimani')));
    await assertSucceeds(getDoc(doc(visitor(), 'config', 'tenant')));
  });
  test('none of them can be written by clients', async () => {
    await assertFails(updateDoc(doc(manager(), 'agents', 'agent-wanjiku'), { rating: 5 }));
    await assertFails(setDoc(doc(manager(), 'areas', 'karen'), { name: 'Karen' }));
    await assertFails(setDoc(doc(manager(), 'config', 'tenant'), { id: 'x' }));
  });
});

describe('leads (personal data)', () => {
  test('the public and plain users cannot read leads', async () => {
    await assertFails(getDoc(doc(visitor(), 'leads', 'lead-001')));
    await assertFails(getDoc(doc(user(), 'leads', 'lead-001')));
  });
  test('agents see only their own leads; managers see all', async () => {
    await assertSucceeds(getDoc(doc(agent('agent-wanjiku'), 'leads', 'lead-001')));
    await assertFails(getDoc(doc(agent('agent-otieno'), 'leads', 'lead-001')));
    await assertSucceeds(getDocs(query(collection(agent('agent-wanjiku'), 'leads'), where('agentId', '==', 'agent-wanjiku'))));
    await assertFails(getDocs(collection(agent('agent-wanjiku'), 'leads')));
    await assertSucceeds(getDoc(doc(manager(), 'leads', 'lead-001')));
  });
  test('leads are created and moved only by Functions', async () => {
    await assertFails(setDoc(doc(visitor(), 'leads', 'spam'), { agentId: 'agent-wanjiku', stage: 'new' }));
    await assertFails(updateDoc(doc(agent('agent-wanjiku'), 'leads', 'lead-001'), { stage: 'won' }));
    await assertFails(deleteDoc(doc(manager(), 'leads', 'lead-001')));
  });
});

describe('viewings and payments', () => {
  test('viewings follow the lead rules', async () => {
    await assertFails(getDoc(doc(visitor(), 'viewings', 'view-1')));
    await assertSucceeds(getDoc(doc(agent('agent-wanjiku'), 'viewings', 'view-1')));
    await assertFails(getDoc(doc(agent('agent-otieno'), 'viewings', 'view-1')));
    await assertFails(updateDoc(doc(agent('agent-wanjiku'), 'viewings', 'view-1'), { status: 'confirmed' }));
  });
  test('payments: managers read, nobody writes', async () => {
    await assertFails(getDoc(doc(agent(), 'payments', 'pay-1')));
    await assertSucceeds(getDoc(doc(manager(), 'payments', 'pay-1')));
    await assertFails(updateDoc(doc(manager(), 'payments', 'pay-1'), { status: 'paid' }));
    await assertFails(setDoc(doc(user(), 'payments', 'fake'), { status: 'paid', amountKES: 1 }));
  });
});

describe('audit', () => {
  test('owners and managers read the audit log; agents and the public cannot; nobody writes', async () => {
    await assertSucceeds(getDoc(doc(manager(), 'audit', 'a-1')));
    await assertSucceeds(getDoc(doc(env.authenticatedContext('own', { role: 'owner' }).firestore(), 'audit', 'a-1')));
    await assertFails(getDoc(doc(agent(), 'audit', 'a-1')));
    await assertFails(getDoc(doc(visitor(), 'audit', 'a-1')));
    await assertFails(setDoc(doc(manager(), 'audit', 'a-2'), { action: 'listing.approve' }));
    await assertFails(deleteDoc(doc(manager(), 'audit', 'a-1')));
  });
});

describe('savedSearches', () => {
  const mine = { userId: 'alice', filters: { purpose: 'rent', areas: ['kilimani'] }, channels: ['push'], lastNotifiedAt: null };
  test('a user creates, reads, edits and deletes their own', async () => {
    await assertSucceeds(setDoc(doc(user(), 'savedSearches', 'ss-2'), { ...mine, createdAt: serverTimestamp() }));
    await assertSucceeds(getDoc(doc(user(), 'savedSearches', 'ss-1')));
    await assertSucceeds(updateDoc(doc(user(), 'savedSearches', 'ss-1'), { channels: ['push', 'email'] }));
    await assertSucceeds(deleteDoc(doc(user(), 'savedSearches', 'ss-1')));
  });
  test("nobody touches someone else's, or the fields Functions own", async () => {
    await assertFails(getDoc(doc(user('bob'), 'savedSearches', 'ss-1')));
    await assertFails(setDoc(doc(user('bob'), 'savedSearches', 'ss-3'), { ...mine, createdAt: serverTimestamp() }));
    await assertFails(setDoc(doc(visitor(), 'savedSearches', 'ss-4'), { ...mine, createdAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(user(), 'savedSearches', 'ss-1'), { lastNotifiedAt: new Date() }));
    await assertFails(updateDoc(doc(user(), 'savedSearches', 'ss-1'), { userId: 'bob' }));
    await assertFails(setDoc(doc(user(), 'savedSearches', 'ss-5'), { ...mine, admin: true, createdAt: serverTimestamp() }));
  });
});

describe('everything else', () => {
  test('unknown collections are closed', async () => {
    await assertFails(getDoc(doc(manager(), 'secrets', 'x')));
    await assertFails(setDoc(doc(manager(), 'commissions', 'x'), { amountKES: 1 }));
  });
});
