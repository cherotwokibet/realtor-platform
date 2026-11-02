import type { Firestore, Transaction } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { docId } from '../model/schema';
import { audit } from './audit';
import { type Caller, isManager, parseInput, requireStaff } from './auth';

/**
 * Agent availability (P5-s05): an agent blocks out time (leave, a meeting,
 * a day off) and no viewing can be booked or moved into it. Blocks live in
 * `agentBlocks`; staff read them (rules), only these Functions write them.
 * The note is for the team and never reaches clients.
 */
export const MAX_BLOCK_DAYS = 31;

export const addBlockInput = z.object({
  /** Managers block for any agent; an agent always for themself. */
  agentId: docId.optional(),
  start: z.iso.datetime({ offset: true }),
  end: z.iso.datetime({ offset: true }),
  note: z.string().trim().max(120).optional(),
});

export const removeBlockInput = z.object({ blockId: docId });

/** "26 Oct, 10:30" in Nairobi time. */
const nairobi = (d: Date) =>
  d.toLocaleString('en-KE', { timeZone: 'Africa/Nairobi', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false });

export async function addAgentBlock(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ blockId: string }> {
  requireStaff(caller);
  const req = parseInput(addBlockInput, input);
  const agentId = isManager(caller) ? req.agentId : caller.agentId;
  if (!agentId) throw new HttpsError('invalid-argument', 'agentId: pick an agent');
  const start = new Date(req.start), end = new Date(req.end);
  if (end <= start) throw new HttpsError('invalid-argument', 'end: must be after the start');
  if (end <= now) throw new HttpsError('invalid-argument', 'end: that time has passed');
  if (end.getTime() - start.getTime() > MAX_BLOCK_DAYS * 86_400_000) throw new HttpsError('invalid-argument', `end: at most ${MAX_BLOCK_DAYS} days at a time`);
  const agent = await db.collection('agents').doc(agentId).get();
  if (!agent.exists) throw new HttpsError('not-found', `no agent "${agentId}"`);
  const ref = db.collection('agentBlocks').doc();
  await db.runTransaction(async (tx) => {
    tx.create(ref, { agentId, start, end, ...(req.note ? { note: req.note } : {}), createdBy: caller.uid, createdAt: now });
    audit(tx, db, caller, {
      action: 'agent.block',
      target: { collection: 'agents', id: agentId, label: `${agent.get('name') ?? agentId}: ${nairobi(start)} to ${nairobi(end)}` },
    }, now);
  });
  return { blockId: ref.id };
}

export async function removeAgentBlock(db: Firestore, caller: Caller, input: unknown, now = new Date()): Promise<{ removed: true }> {
  requireStaff(caller);
  const req = parseInput(removeBlockInput, input);
  const ref = db.collection('agentBlocks').doc(req.blockId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError('not-found', 'no such block');
    const agentId = snap.get('agentId') as string;
    if (!isManager(caller) && agentId !== caller.agentId) throw new HttpsError('permission-denied', 'not your time off');
    tx.delete(ref);
    audit(tx, db, caller, {
      action: 'agent.unblock',
      target: { collection: 'agents', id: agentId, label: `${agentId}: ${nairobi(snap.get('start').toDate())} to ${nairobi(snap.get('end').toDate())}` },
    }, now);
  });
  return { removed: true };
}

/**
 * Refuses [slot] (a 30-minute viewing) when it overlaps one of the agent's
 * blocks. Read inside the booking transaction. Blocks are at most a month
 * long, so only those ending after the slot starts and starting within a
 * month before it can overlap.
 */
export async function assertAgentFree(tx: Transaction, db: Firestore, agentId: string, slot: Date, slotMinutes: number): Promise<void> {
  const slotEnd = new Date(slot.getTime() + slotMinutes * 60_000);
  const q = db.collection('agentBlocks').where('agentId', '==', agentId).where('end', '>', slot).orderBy('end').limit(50);
  const blocks = await tx.get(q);
  if (blocks.docs.some((b) => (b.get('start').toDate() as Date) < slotEnd)) {
    throw new HttpsError('already-exists', 'the agent is not available then, pick another time');
  }
}
