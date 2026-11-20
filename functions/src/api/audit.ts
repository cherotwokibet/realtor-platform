import type { DocumentData, DocumentReference, Firestore } from 'firebase-admin/firestore';
import type { Caller } from './auth';

/** What a staff action did, for the admin's audit log (owner and manager read it). */
export interface AuditEvent {
  action:
    | 'lead.stage'
    | 'lead.followup'
    | 'listing.submit'
    | 'listing.approve'
    | 'listing.reject'
    | 'listing.expire'
    | 'listing.let'
    | 'listing.sold'
    | 'listing.confirm'
    | 'listing.feature'
    | 'listing.hot'
    | 'listing.recommend'
    | 'listing.pin-newest'
    | 'listing.edit'
    | 'listing.edit-request'
    | 'listing.edit-approve'
    | 'listing.edit-reject'
    | 'viewing.status'
    | 'viewing.reschedule'
    | 'agent.block'
    | 'agent.unblock'
    | 'agent.save'
    | 'area.save'
    | 'review.moderate'
    | 'page.save'
    | 'project.save'
    | 'staff.role'
    | 'privacy.export'
    | 'privacy.delete'
    | 'feedback.update'
    | 'ad.save'
    | 'ad.delete';
  /** label: what the admin shows for it (a listing title, a staff email), kept as it was then. */
  target: {
    collection: 'leads' | 'listings' | 'staff' | 'people' | 'viewings' | 'agents' | 'areas' | 'pages' | 'projects' | 'feedback' | 'ads';
    id: string;
    label?: string;
  };
  from?: string | null;
  to?: string;
  reason?: string;
}

/** A transaction or a write batch. */
type Writer = { set(ref: DocumentReference, data: DocumentData): unknown };

/**
 * Records [event] in the same transaction (or batch) as the change, so an
 * entry exists exactly when the change does. Ids and states only, plus the
 * acting staff member's name.
 */
export function audit(tx: Writer, db: Firestore, caller: Caller, event: AuditEvent, at: Date): void {
  const ref = db.collection('audit').doc();
  const entry = {
    at,
    actor: { uid: caller.uid, role: caller.role, agentId: caller.agentId, name: caller.name ?? null },
    action: event.action,
    target: { collection: event.target.collection, id: event.target.id, label: event.target.label ?? null },
    from: event.from ?? null,
    to: event.to ?? null,
    ...(event.reason ? { reason: event.reason } : {}),
  };
  tx.set(ref, entry);
}
