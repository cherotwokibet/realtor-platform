/**
 * Storage rules tests (needs the Firestore and Storage emulators):
 *   firebase emulators:exec --only firestore,storage --project demo-realtor "npm --prefix functions run test:rules"
 */
import { after, before, test } from 'node:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { ref, uploadBytes, getBytes } from 'firebase/storage';

let env: RulesTestEnvironment;
const root = join(__dirname, '..', '..', '..');
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const img = { contentType: 'image/jpeg' };

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-realtor',
    storage: { rules: readFileSync(join(root, 'storage.rules'), 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), 'media/listings/listing-001/abc/card.webp'), jpeg, { contentType: 'image/webp' });
  });
});

after(async () => env?.cleanup());

const visitor = () => env.unauthenticatedContext().storage();
const agent = (agentId: string) => env.authenticatedContext(`u-${agentId}`, { role: 'agent', agentId }).storage();
const manager = () => env.authenticatedContext('boss', { role: 'manager' }).storage();

const mine = 'uploads/agents/agent-wanjiku/listings/listing-001';

test('agents upload only into their own folder; managers into theirs', async () => {
  await assertSucceeds(uploadBytes(ref(agent('agent-wanjiku'), `${mine}/a.jpg`), jpeg, img));
  await assertSucceeds(uploadBytes(ref(manager(), 'uploads/staff/boss/listings/listing-001/b.jpg'), jpeg, img));
  await assertFails(uploadBytes(ref(agent('agent-otieno'), `${mine}/c.jpg`), jpeg, img));
  await assertFails(uploadBytes(ref(manager(), 'uploads/staff/someone-else/listings/listing-001/b.jpg'), jpeg, img));
  await assertFails(uploadBytes(ref(visitor(), `${mine}/d.jpg`), jpeg, img));
  await assertFails(uploadBytes(ref(env.authenticatedContext('alice').storage(), `${mine}/e.jpg`), jpeg, img));
});

test('videos are allowed in uploads/, other types are not', async () => {
  const clip = new Uint8Array(1024);
  await assertSucceeds(uploadBytes(ref(agent('agent-wanjiku'), `${mine}/walk.mp4`), clip, { contentType: 'video/mp4' }));
  await assertFails(uploadBytes(ref(agent('agent-wanjiku'), `${mine}/walk.avi`), clip, { contentType: 'video/x-msvideo' }));
});

test('only images under 20 MB, and no raw reads', async () => {
  await assertFails(uploadBytes(ref(agent('agent-wanjiku'), `${mine}/x.pdf`), jpeg, { contentType: 'application/pdf' }));
  await assertFails(getBytes(ref(agent('agent-wanjiku'), `${mine}/a.jpg`)));
});

test('variants are public; nobody writes media/ or brand/', async () => {
  await assertSucceeds(getBytes(ref(visitor(), 'media/listings/listing-001/abc/card.webp')));
  await assertFails(uploadBytes(ref(manager(), 'media/listings/listing-001/abc/card.webp'), jpeg, { contentType: 'image/webp' }));
  await assertFails(uploadBytes(ref(manager(), 'brand/watermark.png'), jpeg, { contentType: 'image/png' }));
  await assertFails(uploadBytes(ref(manager(), 'anything/else.jpg'), jpeg, img));
});
