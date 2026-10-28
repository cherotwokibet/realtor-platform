/**
 * Agent response times (P5-s03). Each lead records how long its agent took
 * to move it on from "new" (updateLeadStage). Nightly, every agent's
 * `responseMins` becomes the median of their last RESPONSE_WINDOW_DAYS of
 * responses, shown on share pages ("Usually replies within ...") and in the
 * admin. Too few responses to say anything fair leaves it null.
 */
import type { Firestore } from 'firebase-admin/firestore';

export const RESPONSE_WINDOW_DAYS = 90;
export const MIN_RESPONSES = 3;

export function median(values: number[]): number | null {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b);
  const mid = s.length >> 1;
  return s.length % 2 ? s[mid] : Math.round((s[mid - 1] + s[mid]) / 2);
}

/** Writes `responseMins` on every agent; returns agentId -> minutes (or null). */
export async function updateAgentResponseTimes(db: Firestore, now = new Date()): Promise<Record<string, number | null>> {
  const since = new Date(now.getTime() - RESPONSE_WINDOW_DAYS * 86_400_000);
  const leads = await db.collection('leads').where('firstResponseAt', '>=', since).select('agentId', 'responseMins').get();
  const byAgent = new Map<string, number[]>();
  for (const d of leads.docs) {
    const mins = d.get('responseMins');
    if (typeof mins !== 'number') continue;
    const id = d.get('agentId') as string;
    byAgent.set(id, [...(byAgent.get(id) ?? []), mins]);
  }
  const agents = await db.collection('agents').select('responseMins').get();
  const out: Record<string, number | null> = {};
  const batch = db.batch();
  for (const a of agents.docs) {
    const mins = byAgent.get(a.id) ?? [];
    const value = mins.length >= MIN_RESPONSES ? median(mins) : null;
    out[a.id] = value;
    if (a.get('responseMins') !== value) batch.update(a.ref, { responseMins: value });
  }
  await batch.commit();
  return out;
}
