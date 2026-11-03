/**
 * Data model v2: one schema per Firestore collection. Functions validate
 * every write with these; the seed data must pass them too. Field notes and
 * who may write what are in docs/data-model.md.
 */
import { z } from 'zod';
import { isValidKes } from '../listing-rules';

export const kes = z.number().refine(isValidKes, 'whole shillings, 0 to 10 billion');
export const kenyanPhone = z.string().regex(/^\+254[17]\d{8}$/, 'E.164 Kenyan mobile, e.g. +254712345678');
export const slug = z.string().regex(/^[a-z0-9]+(-[a-z0-9]+)*$/).max(80);
export const docId = z.string().min(1).max(128);
const timestamp = z.date();

export const geoPoint = z.object({
  lat: z.number().min(-90).max(90),
  lng: z.number().min(-180).max(180),
  geohash: z.string().regex(/^[0-9b-hjkmnp-z]{9}$/),
});

export const listingPurpose = z.enum(['rent', 'sale', 'short-stay']);
export const listingType = z.enum([
  'bedsitter', 'single-room', 'studio', 'apartment', 'maisonette', 'townhouse',
  'bungalow', 'villa', 'hostel', 'land', 'commercial',
]);
export const listingStatus = z.enum(['draft', 'pending', 'live', 'expired', 'let', 'sold']);

export const mediaItem = z.object({
  kind: z.enum(['photo', 'video', 'floor-plan', 'tour-360']),
  /** Storage paths written by the media pipeline (P2-s04): thumb / card / full, or hls. */
  variants: z.record(z.string(), z.string()),
  blurhash: z.string().optional(),
  width: z.number().int().positive().optional(),
  height: z.number().int().positive().optional(),
  /** dHash (16 hex digits) for duplicate detection, set by the media pipeline. */
  phash: z.string().regex(/^[0-9a-f]{16}$/).optional(),
});

export const listing = z
  .object({
    title: z.string().min(5).max(120),
    slug,
    purpose: listingPurpose,
    type: listingType,
    beds: z.number().int().min(0).max(20),
    baths: z.number().int().min(0).max(20),
    /** Monthly rent, nightly rate (short-stay) or sale price. */
    priceKES: kes,
    /** Rent deposit in months. */
    depositMonths: z.number().int().min(0).max(12).optional(),
    serviceChargeKES: kes.optional(),
    geo: geoPoint,
    /** areas/{slug} */
    area: slug,
    estate: z.string().max(80).optional(),
    /** The listing's text (P7-s02): the agent's own words, or a suggestion they edited. */
    description: z.string().max(3000).optional(),
    amenities: z.array(z.string().max(40)).max(40),
    utilities: z.object({ water: z.boolean(), electricity: z.boolean(), wifi: z.boolean() }).partial(),
    media: z.array(mediaItem).max(60),
    agentId: docId,
    // Functions-only fields (D7):
    status: listingStatus,
    verifiedAt: timestamp.nullable(),
    expiresAt: timestamp.nullable(),
    featuredUntil: timestamp.nullable(),
    stats: z.object({
      views: z.number().int().min(0),
      leads: z.number().int().min(0),
      /** Call and WhatsApp taps (D13): counted, no personal data. */
      calls: z.number().int().min(0).optional(),
      whatsapps: z.number().int().min(0).optional(),
    }),
    createdAt: timestamp,
    updatedAt: timestamp,
  })
  .refine((l) => l.purpose !== 'rent' || l.depositMonths !== undefined, {
    message: 'rent listings state the deposit in months',
    path: ['depositMonths'],
  });

export const agent = z.object({
  name: z.string().min(2).max(80),
  photo: z.string().optional(),
  earbNo: z.string().max(40),
  phone: kenyanPhone,
  whatsapp: kenyanPhone,
  languages: z.array(z.enum(['en', 'sw'])).min(1),
  rating: z.number().min(0).max(5).nullable(),
  /** How many approved reviews the rating is from (P6-s03). */
  ratingCount: z.number().int().min(0).optional(),
  responseMins: z.number().int().min(0).nullable(),
  active: z.boolean(),
});

export const leadChannel = z.enum(['call', 'whatsapp', 'form', 'viewing']);
export const leadStage = z.enum(['new', 'contacted', 'viewing', 'offer', 'won', 'lost']);

/** Data Protection Act 2019: consent time and a retention date on every lead. */
export const lead = z
  .object({
    listingId: docId.nullable(),
    agentId: docId,
    channel: leadChannel,
    contact: z.object({ name: z.string().max(80).optional(), phone: kenyanPhone.optional(), email: z.email().optional() }),
    message: z.string().max(2000).optional(),
    stage: leadStage,
    consentAt: timestamp,
    retainUntil: timestamp,
    createdAt: timestamp,
    /** When the agent first moved it on from new, and how many minutes that took (P5-s03). */
    firstResponseAt: timestamp.optional(),
    responseMins: z.number().int().min(0).optional(),
  })
  .refine((l) => l.contact.phone || l.contact.email, { message: 'a lead needs a phone or an email', path: ['contact'] })
  .refine((l) => l.retainUntil > l.consentAt, { message: 'retainUntil must be after consentAt', path: ['retainUntil'] });

export const viewing = z.object({
  listingId: docId,
  agentId: docId,
  slot: timestamp,
  client: z.object({ name: z.string().max(80), phone: kenyanPhone }),
  status: z.enum(['requested', 'confirmed', 'done', 'no-show', 'cancelled']),
  feeKES: kes,
  /** payments/{id} when a viewing fee was paid by M-Pesa. */
  paymentId: docId.nullable(),
  createdAt: timestamp,
});

export const payment = z.object({
  purpose: z.enum(['viewing-fee', 'deposit', 'featured-ad']),
  amountKES: kes.refine((n) => n >= 1, 'at least KES 1'),
  phone: kenyanPhone,
  listingId: docId.nullable(),
  /** Daraja STK Push ids and result (P6). */
  checkoutRequestId: z.string().nullable(),
  status: z.enum(['pending', 'paid', 'failed', 'cancelled']),
  receipt: z.string().nullable(),
  /** The viewing a viewing fee is for. */
  viewingId: docId.optional(),
  merchantRequestId: z.string().nullable().optional(),
  /** Random, per payment: the callback URL carries it, so only Safaricom's callback for this push settles it. */
  callbackToken: z.string().optional(),
  /** Why a payment failed or was cancelled. */
  reason: z.string().max(200).nullable().optional(),
  attempts: z.number().int().min(1).optional(),
  createdAt: timestamp,
  updatedAt: timestamp,
});

export const savedSearch = z.object({
  userId: docId,
  filters: z.object({
    purpose: listingPurpose,
    types: z.array(listingType).optional(),
    areas: z.array(slug).optional(),
    minBeds: z.number().int().min(0).optional(),
    maxPriceKES: kes.optional(),
  }),
  /** inbox: alerts in the app (D18); email and push once their senders are set up. */
  channels: z.array(z.enum(['inbox', 'push', 'email', 'whatsapp'])).min(1),
  lastNotifiedAt: timestamp.nullable(),
  createdAt: timestamp,
});

export const area = z.object({
  name: z.string().min(2).max(60),
  county: z.string().min(2).max(40),
  centre: geoPoint,
  guide: z.string().max(5000),
  amenities: z.array(z.string().max(60)),
  stats: z.object({ medianRentKES: kes.nullable(), listings: z.number().int().min(0) }),
});

/** Off-plan projects (P5-s06): see api/projects.ts. */
export const UNIT_TYPES = ['studio', 'apartment', 'maisonette', 'townhouse', 'villa', 'plot', 'commercial'] as const;
export const projectUnit = z.object({
  type: z.enum(UNIT_TYPES),
  beds: z.number().int().min(0).max(10),
  sizeSqm: z.number().int().min(10).max(5000).optional(),
  fromKES: z.number().int().min(100_000).max(2_000_000_000),
  available: z.number().int().min(0).max(5000),
});
export const paymentStage = z.object({ stage: z.string().trim().min(2).max(60), percent: z.number().int().min(1).max(100) });
export const project = z.object({
  name: z.string().min(3).max(80),
  developer: z.string().min(2).max(80),
  area: slug,
  summary: z.string().max(5000),
  completion: z.string().regex(/^20\d\d-(0[1-9]|1[0-2])$/),
  units: z.array(projectUnit).min(1).max(20),
  paymentPlan: z.array(paymentStage).min(1).max(12),
  fromKES: z.number().int().min(0),
  published: z.boolean(),
  updatedAt: timestamp,
});

/** Collection name -> schema. config/tenant is validated by tenants/schema instead. */
export const collections = {
  listings: listing,
  agents: agent,
  leads: lead,
  viewings: viewing,
  payments: payment,
  savedSearches: savedSearch,
  areas: area,
  projects: project,
} as const;

export type CollectionName = keyof typeof collections;
export type Listing = z.infer<typeof listing>;
export type Agent = z.infer<typeof agent>;
export type Lead = z.infer<typeof lead>;
export type Area = z.infer<typeof area>;
