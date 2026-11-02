import type { Firestore } from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { z } from 'zod';
import { median } from './response';
import { recommendationTotals, type RecommendationTotals } from './recommendations';
import { type Caller, parseInput, requireManager } from './auth';

/**
 * Monthly report (P5-s08), owners and managers: the month's leads (by
 * channel and by the stage they have reached), viewings (by status), each
 * agent's numbers, and the listings with the most leads so far. Counts
 * only, never a client's name or number. Revenue and commission come with
 * M-Pesa (P6-s01).
 */
export const monthlyReportInput = z.object({ month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'YYYY-MM') });

export interface AgentRow {
  agentId: string;
  name: string;
  leads: number;
  won: number;
  viewingsDone: number;
  noShows: number;
  /** Median minutes to first reply on this month's leads; null under 1 reply. */
  replyMins: number | null;
}

export interface MonthlyReport {
  month: string;
  leads: { total: number; byChannel: Record<string, number>; byStage: Record<string, number> };
  viewings: { total: number; byStatus: Record<string, number> };
  agents: AgentRow[];
  topListings: { listingId: string; title: string; agentId: string; leads: number; calls: number; whatsapps: number }[];
  /** "Similar homes" shown under listings and homes opened from it (P7-s04). */
  recommendations: RecommendationTotals;
}

/** First and last instant of a Nairobi month (UTC+3 all year). */
export function monthRange(month: string): { start: Date; end: Date } {
  const [y, m] = month.split('-').map(Number);
  return { start: new Date(Date.UTC(y, m - 1, 1) - 3 * 3_600_000), end: new Date(Date.UTC(y, m, 1) - 3 * 3_600_000) };
}

const count = (rec: Record<string, number>, key: string) => {
  rec[key] = (rec[key] ?? 0) + 1;
};

export async function monthlyReport(db: Firestore, caller: Caller, input: unknown): Promise<MonthlyReport> {
  requireManager(caller);
  const { month } = parseInput(monthlyReportInput, input);
  const { start, end } = monthRange(month);
  const [leads, viewings, agents, listings, recommendations] = await Promise.all([
    db.collection('leads').where('createdAt', '>=', start).where('createdAt', '<', end).select('agentId', 'channel', 'stage', 'responseMins').get(),
    db.collection('viewings').where('slot', '>=', start).where('slot', '<', end).select('agentId', 'status').get(),
    db.collection('agents').select('name').get(),
    db.collection('listings').orderBy('stats.leads', 'desc').limit(10).select('title', 'agentId', 'stats').get(),
    // Day docs are named by date, so the month is a key range (the 31st is past any month's end).
    recommendationTotals(db, `${month}-01`, `${month}-31`),
  ]);
  if (leads.size > 20_000) throw new HttpsError('resource-exhausted', 'too many leads for one report');

  const rows = new Map<string, AgentRow & { replies: number[] }>();
  const row = (agentId: string) => {
    let r = rows.get(agentId);
    if (!r) {
      r = { agentId, name: agentId, leads: 0, won: 0, viewingsDone: 0, noShows: 0, replyMins: null, replies: [] };
      rows.set(agentId, r);
    }
    return r;
  };
  for (const a of agents.docs) row(a.id).name = (a.get('name') as string) ?? a.id;

  const report: MonthlyReport = {
    month,
    leads: { total: leads.size, byChannel: {}, byStage: {} },
    viewings: { total: viewings.size, byStatus: {} },
    agents: [],
    topListings: [],
    recommendations,
  };
  for (const l of leads.docs) {
    count(report.leads.byChannel, l.get('channel'));
    count(report.leads.byStage, l.get('stage'));
    const r = row(l.get('agentId'));
    r.leads++;
    if (l.get('stage') === 'won') r.won++;
    const mins = l.get('responseMins');
    if (typeof mins === 'number') r.replies.push(mins);
  }
  for (const v of viewings.docs) {
    count(report.viewings.byStatus, v.get('status'));
    const r = row(v.get('agentId'));
    if (v.get('status') === 'done') r.viewingsDone++;
    if (v.get('status') === 'no-show') r.noShows++;
  }
  report.agents = [...rows.values()]
    .filter((r) => r.leads || r.viewingsDone || r.noShows)
    .map(({ replies, ...r }) => ({ ...r, replyMins: replies.length ? median(replies) : null }))
    .sort((a, b) => b.won - a.won || b.leads - a.leads || a.name.localeCompare(b.name));
  report.topListings = listings.docs
    .map((d) => {
      const s = (d.get('stats') ?? {}) as Record<string, number>;
      return { listingId: d.id, title: d.get('title') as string, agentId: d.get('agentId') as string, leads: s.leads ?? 0, calls: s.calls ?? 0, whatsapps: s.whatsapps ?? 0 };
    })
    .filter((l) => l.leads > 0);
  return report;
}
