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
import { doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, collection, getDocs, query, where, orderBy } from 'firebase/firestore';
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
    await setDoc(doc(db, 'staff', 'u-agent-wanjiku'), { email: 'a@example.com', role: 'agent', agentId: 'agent-wanjiku' });
    await setDoc(doc(db, 'audit', 'a-1'), { at: new Date(), action: 'lead.stage', actor: { uid: 'boss', role: 'manager', agentId: null } });
    await setDoc(doc(db, 'payments', 'pay-1'), { purpose: 'viewing-fee', amountKES: 500, status: 'paid' });
    await setDoc(doc(db, 'viewings', 'view-1'), { listingId: 'listing-001', agentId: 'agent-wanjiku', status: 'requested' });
    await setDoc(doc(db, 'agentBlocks', 'block-1'), { agentId: 'agent-wanjiku', note: 'Leave' });
    await setDoc(doc(db, 'reviews', 'rev-ok'), { agentId: 'agent-wanjiku', rating: 5, status: 'approved' });
    await setDoc(doc(db, 'reviews', 'rev-new'), { agentId: 'agent-wanjiku', rating: 2, status: 'pending' });
    await setDoc(doc(db, 'reviewInvites', 'tok'), { agentId: 'agent-wanjiku' });
    await setDoc(doc(db, 'users', 'alice', 'alerts', 'a1'), { listingId: 'listing-001', readAt: null });
    await setDoc(doc(db, 'pages', 'about'), { title: 'About', body: 'x', published: true });
    await setDoc(doc(db, 'pages', 'faq'), { title: 'FAQ', body: 'draft', published: false });
    await setDoc(doc(db, 'projects', 'live-project'), { name: 'Live', published: true });
    await setDoc(doc(db, 'projects', 'draft-project'), { name: 'Draft', published: false });
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

describe('site pages', () => {
  test('published pages are public; drafts only for managers; nobody writes', async () => {
    await assertSucceeds(getDoc(doc(visitor(), 'pages', 'about')));
    await assertFails(getDoc(doc(visitor(), 'pages', 'faq')));
    await assertFails(getDoc(doc(agent('agent-wanjiku'), 'pages', 'faq')));
    await assertSucceeds(getDoc(doc(manager(), 'pages', 'faq')));
    await assertFails(setDoc(doc(manager(), 'pages', 'about'), { title: 'x', body: 'y', published: true }));
  });
});

describe('off-plan projects', () => {
  test('published projects are public; drafts only for managers; nobody writes', async () => {
    await assertSucceeds(getDoc(doc(visitor(), 'projects', 'live-project')));
    await assertFails(getDoc(doc(visitor(), 'projects', 'draft-project')));
    await assertFails(getDoc(doc(agent('agent-wanjiku'), 'projects', 'draft-project')));
    await assertSucceeds(getDoc(doc(manager(), 'projects', 'draft-project')));
    await assertFails(setDoc(doc(manager(), 'projects', 'live-project'), { name: 'x', published: true }));
  });
});

describe('a customer\'s profile', () => {
  test('only the customer reads their own; nobody writes it from the app (saveMyProfile does)', async () => {
    await env.withSecurityRulesDisabled(async (c) => setDoc(doc(c.firestore(), 'users', 'alice'), { name: 'Alice', whatsapp: '+254712345678' }));
    await assertSucceeds(getDoc(doc(user('alice'), 'users', 'alice')));
    await assertFails(getDoc(doc(user('bob'), 'users', 'alice')));
    await assertFails(getDoc(doc(visitor(), 'users', 'alice')));
    await assertFails(setDoc(doc(user('alice'), 'users', 'alice'), { name: 'Alice', whatsapp: 'not a number' }));
    await assertFails(updateDoc(doc(user('alice'), 'users', 'alice'), { name: 'Al' }));
  });
});

describe('saved-search alerts', () => {
  test('only the owner reads, marks read and clears their alerts; nobody creates them', async () => {
    await assertSucceeds(getDoc(doc(user('alice'), 'users', 'alice', 'alerts', 'a1')));
    await assertFails(getDoc(doc(user('bob'), 'users', 'alice', 'alerts', 'a1')));
    await assertFails(getDoc(doc(manager(), 'users', 'alice', 'alerts', 'a1')));
    await assertSucceeds(updateDoc(doc(user('alice'), 'users', 'alice', 'alerts', 'a1'), { readAt: new Date() }));
    await assertFails(updateDoc(doc(user('alice'), 'users', 'alice', 'alerts', 'a1'), { listingId: 'other' }));
    await assertFails(setDoc(doc(user('alice'), 'users', 'alice', 'alerts', 'a2'), { listingId: 'x', readAt: null }));
    await assertSucceeds(deleteDoc(doc(user('alice'), 'users', 'alice', 'alerts', 'a1')));
  });

  test('only the owner registers and removes a phone for push, in the right shape', async () => {
    const tok = 'fcm-token-abc:APA91b';
    const device = { token: tok, platform: 'android', updatedAt: serverTimestamp() };
    await assertSucceeds(setDoc(doc(user('alice'), 'users', 'alice', 'devices', tok), device));
    await assertSucceeds(setDoc(doc(user('alice'), 'users', 'alice', 'devices', tok), device));
    await assertSucceeds(getDoc(doc(user('alice'), 'users', 'alice', 'devices', tok)));
    await assertFails(getDoc(doc(user('bob'), 'users', 'alice', 'devices', tok)));
    await assertFails(setDoc(doc(user('bob'), 'users', 'alice', 'devices', 'bob-token'), { ...device, token: 'bob-token' }));
    await assertFails(setDoc(doc(visitor(), 'users', 'alice', 'devices', 'v-token'), { ...device, token: 'v-token' }));
    await assertFails(setDoc(doc(user('alice'), 'users', 'alice', 'devices', 'other'), device)); // the id is the token
    await assertFails(setDoc(doc(user('alice'), 'users', 'alice', 'devices', tok), { ...device, platform: 'fax' }));
    await assertFails(setDoc(doc(user('alice'), 'users', 'alice', 'devices', tok), { ...device, admin: true }));
    await assertFails(setDoc(doc(user('alice'), 'users', 'alice', 'devices', tok), { ...device, updatedAt: new Date(0) }));
    await assertFails(deleteDoc(doc(user('bob'), 'users', 'alice', 'devices', tok)));
    await assertSucceeds(deleteDoc(doc(user('alice'), 'users', 'alice', 'devices', tok)));
  });

  test('a saved search may ask for the in-app inbox', async () => {
    await assertSucceeds(setDoc(doc(user('alice'), 'savedSearches', 'ss-inbox'), {
      userId: 'alice', filters: { purpose: 'rent', areas: ['kilimani'] }, channels: ['inbox'], lastNotifiedAt: null, createdAt: serverTimestamp(),
    }));
  });
});

describe('reviews', () => {
  test('approved reviews are public; pending ones only for managers; links for nobody', async () => {
    await assertSucceeds(getDoc(doc(visitor(), 'reviews', 'rev-ok')));
    await assertFails(getDoc(doc(visitor(), 'reviews', 'rev-new')));
    await assertFails(getDoc(doc(agent('agent-wanjiku'), 'reviews', 'rev-new')));
    await assertSucceeds(getDoc(doc(manager(), 'reviews', 'rev-new')));
    await assertFails(getDoc(doc(manager(), 'reviewInvites', 'tok')));
    await assertFails(setDoc(doc(visitor(), 'reviews', 'rev-x'), { rating: 5, status: 'approved' }));
  });
});

describe('agent time off', () => {
  test("staff read their own (managers all); nobody else, and nobody writes", async () => {
    await assertFails(getDoc(doc(visitor(), 'agentBlocks', 'block-1')));
    await assertFails(getDoc(doc(user(), 'agentBlocks', 'block-1')));
    await assertSucceeds(getDoc(doc(agent('agent-wanjiku'), 'agentBlocks', 'block-1')));
    await assertFails(getDoc(doc(agent('agent-otieno'), 'agentBlocks', 'block-1')));
    await assertSucceeds(getDoc(doc(manager(), 'agentBlocks', 'block-1')));
    await assertFails(setDoc(doc(agent('agent-wanjiku'), 'agentBlocks', 'block-2'), { agentId: 'agent-wanjiku' }));
    await assertFails(deleteDoc(doc(manager(), 'agentBlocks', 'block-1')));
  });
});

describe('viewings and payments', () => {
  test('viewings follow the lead rules', async () => {
    await assertFails(getDoc(doc(visitor(), 'viewings', 'view-1')));
    await assertSucceeds(getDoc(doc(agent('agent-wanjiku'), 'viewings', 'view-1')));
    await assertFails(getDoc(doc(agent('agent-otieno'), 'viewings', 'view-1')));
    await assertFails(updateDoc(doc(agent('agent-wanjiku'), 'viewings', 'view-1'), { status: 'confirmed' }));
    // The admin's Viewings queries (P5-s05): an agent's own, a manager's all.
    const open = (db: ReturnType<typeof manager>, agentId?: string) =>
      getDocs(query(collection(db, 'viewings'), ...(agentId ? [where('agentId', '==', agentId)] : []),
        where('status', 'in', ['requested', 'confirmed']), orderBy('slot')));
    await assertSucceeds(open(agent('agent-wanjiku'), 'agent-wanjiku'));
    await assertFails(open(agent('agent-wanjiku')));
    await assertFails(open(agent('agent-wanjiku'), 'agent-otieno'));
    await assertSucceeds(open(manager()));
  });
  test('payments: managers read, nobody writes', async () => {
    await assertFails(getDoc(doc(agent(), 'payments', 'pay-1')));
    await assertSucceeds(getDoc(doc(manager(), 'payments', 'pay-1')));
    await assertFails(updateDoc(doc(manager(), 'payments', 'pay-1'), { status: 'paid' }));
    await assertFails(setDoc(doc(user(), 'payments', 'fake'), { status: 'paid', amountKES: 1 }));
  });
});

describe('staff', () => {
  test('managers list the team; staff read their own entry; nobody writes', async () => {
    await assertSucceeds(getDocs(collection(manager(), 'staff')));
    await assertSucceeds(getDoc(doc(agent('agent-wanjiku'), 'staff', 'u-agent-wanjiku')));
    await assertFails(getDoc(doc(agent('agent-otieno'), 'staff', 'u-agent-wanjiku')));
    await assertFails(getDocs(collection(agent(), 'staff')));
    await assertFails(getDoc(doc(visitor(), 'staff', 'u-agent-wanjiku')));
    await assertFails(setDoc(doc(user('alice'), 'staff', 'alice'), { role: 'owner' }));
    await assertFails(updateDoc(doc(manager(), 'staff', 'u-agent-wanjiku'), { role: 'manager' }));
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

describe('listingEdits', () => {
  test("managers read every edit waiting; an agent only their own; nobody writes", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'listingEdits', 'l-1'), { listingId: 'l-1', agentId: 'agent-wanjiku', status: 'pending', proposed: { priceKES: 1 } });
    });
    await assertSucceeds(getDoc(doc(manager(), 'listingEdits', 'l-1')));
    await assertSucceeds(getDoc(doc(agent('agent-wanjiku'), 'listingEdits', 'l-1')));
    await assertFails(getDoc(doc(agent('agent-otieno'), 'listingEdits', 'l-1')));
    await assertFails(getDoc(doc(visitor(), 'listingEdits', 'l-1')));
    await assertFails(setDoc(doc(agent('agent-wanjiku'), 'listingEdits', 'l-2'), { listingId: 'l-2', agentId: 'agent-wanjiku', status: 'pending' }));
    await assertFails(updateDoc(doc(manager(), 'listingEdits', 'l-1'), { status: 'approved' }));
  });
});

describe('feedback and ads', () => {
  test('feedback: managers read it; agents and visitors do not; nobody writes it', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'feedback', 'f-1'), { kind: 'question', message: 'Hi there', status: 'new', contact: { phone: '+254700000001' } });
    });
    await assertSucceeds(getDoc(doc(manager(), 'feedback', 'f-1')));
    await assertFails(getDoc(doc(agent(), 'feedback', 'f-1')));
    await assertFails(getDoc(doc(visitor(), 'feedback', 'f-1')));
    await assertFails(setDoc(doc(visitor(), 'feedback', 'f-2'), { kind: 'question', message: 'Hi there' }));
  });
  test('ads: anyone reads those switched on; managers read all; nobody writes', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ads', 'on'), { title: 'On', active: true });
      await setDoc(doc(ctx.firestore(), 'ads', 'off'), { title: 'Off', active: false });
    });
    await assertSucceeds(getDoc(doc(visitor(), 'ads', 'on')));
    await assertFails(getDoc(doc(visitor(), 'ads', 'off')));
    await assertSucceeds(getDoc(doc(manager(), 'ads', 'off')));
    await assertFails(setDoc(doc(manager(), 'ads', 'x'), { title: 'X', active: true }));
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
  test('only the shape the sweep expects: known filters, bounded lists, known channels', async () => {
    const make = (over: object) => setDoc(doc(user(), 'savedSearches', `ss-${Math.random()}`), { ...mine, ...over, createdAt: serverTimestamp() });
    await assertSucceeds(make({ filters: { purpose: 'sale', types: ['apartment'], areas: ['kilimani'], minBeds: 2, maxPriceKES: 15000000 } }));
    await assertFails(make({ filters: { purpose: 'rent', notes: 'x'.repeat(5000) } }));
    await assertFails(make({ filters: { purpose: 'lease' } }));
    await assertFails(make({ filters: { purpose: 'rent', areas: Array.from({ length: 21 }, (_, i) => `area-${i}`) } }));
    await assertFails(make({ filters: { purpose: 'rent', minBeds: 2.5 } }));
    await assertFails(make({ channels: ['sms'] }));
    await assertFails(updateDoc(doc(user(), 'savedSearches', 'ss-1'), { channels: ['push', 'fax'] }));
    await assertFails(updateDoc(doc(user(), 'savedSearches', 'ss-1'), { filters: { purpose: 'rent', junk: true } }));
  });
  test('the same search saved twice (the id comes from the search) is refused the second time', async () => {
    const again = () => setDoc(doc(user(), 'savedSearches', 'alice-samekey'), { ...mine, createdAt: serverTimestamp() });
    await assertSucceeds(again());
    await assertFails(again());
  });
  test('a drawn area: 3 to 20 corners written as the search link writes them', async () => {
    const make = (poly: unknown) => setDoc(doc(user(), 'savedSearches', `ss-${Math.random()}`), { ...mine, filters: { purpose: 'rent', poly }, createdAt: serverTimestamp() });
    const area = (n: number) => Array.from({ length: n }, (_, i) => `${(-1.28 - i / 1000).toFixed(5)},${(36.78 + i / 1000).toFixed(5)}`).join('~');
    await assertSucceeds(make(area(4)));
    await assertSucceeds(make(area(20)));
    await assertSucceeds(make('-1.2,36.8~-1.21,36.81~-1.22,36.8'));
    await assertFails(make(area(2)));
    await assertFails(make(area(21)));
    await assertFails(make(`${area(3)}~<script>`));
    await assertFails(make(`${area(3)} DROP`));
    await assertFails(make([{ lat: -1.28, lng: 36.78 }, { lat: -1.29, lng: 36.79 }, { lat: -1.3, lng: 36.8 }]));
  });
});

describe('photo flags (P6-s05)', () => {
  test('managers read flags; agents and visitors do not; nobody reads the hash index', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'photoFlags', 'listing-002_abc'), { listingId: 'listing-002', mediaId: 'abc', matches: [] });
      await setDoc(doc(ctx.firestore(), 'photoHashes', '0_ab'), { entries: [] });
    });
    await assertSucceeds(getDoc(doc(manager(), 'photoFlags', 'listing-002_abc')));
    await assertFails(getDoc(doc(agent(), 'photoFlags', 'listing-002_abc')));
    await assertFails(getDoc(doc(visitor(), 'photoFlags', 'listing-002_abc')));
    await assertFails(setDoc(doc(manager(), 'photoFlags', 'x'), { listingId: 'x' }));
    await assertFails(getDoc(doc(manager(), 'photoHashes', '0_ab')));
  });
});

describe('everything else', () => {
  test('unknown collections are closed', async () => {
    await assertFails(getDoc(doc(manager(), 'secrets', 'x')));
    await assertFails(setDoc(doc(manager(), 'commissions', 'x'), { amountKES: 1 }));
  });

  test('a visitor (no sign-in) can write nothing, in any collection (P0-s03)', async () => {
    const paths: [string, string][] = [
      ['listings', 'listing-001'], ['listings', 'new'], ['agents', 'agent-wanjiku'], ['areas', 'kilimani'], ['config', 'tenant'],
      ['leads', 'x'], ['viewings', 'x'], ['projects', 'x'], ['pages', 'about'], ['users/u1/alerts', 'x'], ['reviews', 'x'],
      ['reviewInvites', 'x'], ['agentBlocks', 'x'], ['payments', 'x'], ['staff', 'x'], ['audit', 'x'], ['photoFlags', 'x'],
      ['savedSearches', 'x'], ['photoHashes', 'x'], ['rateLimits', 'x'], ['commissions', 'x'],
    ];
    for (const [col, id] of paths) {
      const ref = doc(visitor(), col, id);
      await assertFails(setDoc(ref, { status: 'live', priceKES: 1 }));
      await assertFails(updateDoc(ref, { status: 'live' }));
      await assertFails(deleteDoc(ref));
    }
  });

  test('rate-limit counters are Functions-only', async () => {
    await assertFails(getDoc(doc(manager(), 'rateLimits', 'x')));
    await assertFails(setDoc(doc(manager(), 'rateLimits', 'x'), { count: 0 }));
  });
});
