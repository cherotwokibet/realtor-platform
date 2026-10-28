import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId, kenyanPhone } from '../model/schema';
import { slugify } from '../model/geo';
import { audit } from './audit';
import { type Caller, parseInput, requireManager } from './auth';

/**
 * Agent profiles (P5-s04), managers only: the public agent page shows
 * name, EARB registration, languages and contacts. A new agent's id comes
 * from the name; `active: false` takes the page down and keeps the record.
 * Photo is set by the media pipeline (uploads/staff/<uid>/agents/<id>/...),
 * rating and responseMins by their own jobs; neither is sent here.
 */
export const saveAgentInput = z.object({
  agentId: docId.optional(),
  name: z.string().trim().min(2).max(80),
  earbNo: z.string().trim().min(1).max(40),
  phone: kenyanPhone,
  whatsapp: kenyanPhone,
  languages: z.array(z.enum(['en', 'sw'])).min(1),
  active: z.boolean(),
});

export async function saveAgent(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ agentId: string }> {
  requireManager(caller);
  const req = parseInput(saveAgentInput, input);
  const { agentId: given, ...fields } = req;
  let agentId = given ?? `agent-${slugify(req.name)}`;
  await db.runTransaction(async (tx) => {
    let ref = db.collection('agents').doc(agentId);
    let snap = await tx.get(ref);
    if (given && !snap.exists) throw new HttpsError('not-found', `no agent "${given}"`);
    // Two agents with one name: the second gets a number.
    for (let n = 2; !given && snap.exists; n++) {
      agentId = `agent-${slugify(req.name)}-${n}`;
      ref = db.collection('agents').doc(agentId);
      snap = await tx.get(ref);
    }
    const before = snap.exists ? (snap.get('active') as boolean) : null;
    if (snap.exists) {
      tx.update(ref, { ...fields, updatedAt: now });
    } else {
      tx.create(ref, { ...fields, rating: null, responseMins: null, createdAt: now, updatedAt: now });
    }
    audit(tx, db, caller, {
      action: 'agent.save',
      target: { collection: 'agents', id: agentId, label: req.name },
      from: before === null ? 'none' : before ? 'active' : 'inactive',
      to: req.active ? 'active' : 'inactive',
    }, now);
  });
  return { agentId };
}
