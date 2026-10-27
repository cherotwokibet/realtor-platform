import type { Firestore, Transaction } from 'firebase-admin/firestore';
import type { Caller } from './auth';

/** What a staff action did, for the admin's audit log (owner and manager read it). */
export interface AuditEvent {
  action: 'lead.stage' | 'listing.submit' | 'listing.approve' | 'listing.reject' | 'listing.expire' | 'listing.let' | 'listing.sold';
  target: { collection: 'leads' | 'listings'; id: string };
  from?: string | null;
  to?: string;
  reason?: string;
}

/**
 * Records [event] in the same transaction as the change, so an entry exists
 * exactly when the change does. No personal data: ids and states only.
 */
export function audit(tx: Transaction, db: Firestore, caller: Caller, event: AuditEvent, at: Date): void {
  tx.set(db.collection('audit').doc(), {
    at,
    actor: { uid: caller.uid, role: caller.role, agentId: caller.agentId },
    action: event.action,
    target: event.target,
    from: event.from ?? null,
    to: event.to ?? null,
    ...(event.reason ? { reason: event.reason } : {}),
  });
}
