/** Server-side business rules for listings. Pure functions, unit-tested. */

import transitions from './model/transitions.json';

export const REGION = 'europe-west1';

/** Listings must be re-confirmed by an agent every 30 days to keep the Verified badge. */
export const VERIFICATION_DAYS = 30;

export type ListingStatus = 'draft' | 'pending' | 'live' | 'expired' | 'let' | 'sold';

export function verificationExpiry(verifiedAt: Date): Date {
  return new Date(verifiedAt.getTime() + VERIFICATION_DAYS * 24 * 60 * 60 * 1000);
}

/**
 * Allowed status moves. Clients can request a move; only Functions apply it.
 * The table is shared with the admin's menus (model/transitions.json).
 */
const MOVES: Record<ListingStatus, readonly ListingStatus[]> = transitions.listingStatus as Record<ListingStatus, ListingStatus[]>;

export function canMove(from: ListingStatus, to: ListingStatus): boolean {
  return MOVES[from].includes(to);
}

/** Whole-shilling amounts only. Rejects decimals, negatives and silly values. */
export function isValidKes(amount: unknown): amount is number {
  return typeof amount === 'number' && Number.isInteger(amount) && amount >= 0 && amount <= 10_000_000_000;
}
