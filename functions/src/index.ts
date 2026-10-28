/**
 * Cloud Functions entry point. Rule D7: anything about money, approval,
 * verification or commissions happens here, never in a client.
 *
 * Callables: createLead, logContactTap, bookViewing, updateLeadStage, submitListing, moderateListing, setStaffRole.
 * Scheduled: purgeExpiredLeads (D12 retention, nightly).
 *
 * Planned (see tracker):
 *   P2  onMediaUpload   -> ffmpeg HLS for video (photos done: onListingPhoto)
 *   P4  sendPush        -> FCM HTTP v1 (replaces the legacy server key)
 *   P6  mpesaStkPush / mpesaCallback -> Daraja
 *   P6  verifyListing / expireListings (scheduled, 30-day re-verification)
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall, onRequest } from 'firebase-functions/v2/https';
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import { Client as Typesense } from 'typesense';
import { type SearchConfig, searchConfig } from './search/config';
import { searchRelevantChange, syncListing } from './search/sync';
import { getStorage } from 'firebase-admin/storage';
import { mediaBucketName } from './media/bucket';
import { handleListingUpload } from './media/upload';
import { callerFrom } from './api/auth';
import * as leads from './api/leads';
import * as listings from './api/listings';
import * as staff from './api/staff';
import * as viewings from './api/viewings';
import { purgeExpired } from './api/retention';
import { REGION, verificationExpiry } from './listing-rules';

initializeApp();

setGlobalOptions({ region: REGION, maxInstances: 10 });

export const health = onRequest((_req, res) => {
  res.json({ ok: true, project: process.env.GCLOUD_PROJECT ?? 'local', region: REGION });
});

// Callable API (P2-s03). Inputs are zod-validated in ./api; the clients
// never write these collections directly (see firestore.rules).
export const createLead = onCall((req) => leads.createLead(getFirestore(), req.data));
export const logContactTap = onCall((req) => leads.logContactTap(getFirestore(), req.data));
export const bookViewing = onCall((req) => viewings.bookViewing(getFirestore(), req.data));
export const updateLeadStage = onCall((req) => leads.updateLeadStage(getFirestore(), callerFrom(req.auth), req.data));
export const submitListing = onCall((req) => listings.submitListing(getFirestore(), callerFrom(req.auth), req.data));
export const moderateListing = onCall((req) => listings.moderateListing(getFirestore(), callerFrom(req.auth), req.data));
export const setStaffRole = onCall((req) => staff.setStaffRole(getFirestore(), getAuth(), callerFrom(req.auth), req.data));

// Retention (D12): every night, delete leads and viewings past their date.
// Only counts are logged, never what was deleted.
export const purgeExpiredLeads = onSchedule({ schedule: '15 3 * * *', timeZone: 'Africa/Nairobi', retryCount: 1 }, async () => {
  const r = await purgeExpired(getFirestore(), new Date());
  console.log(`retention: deleted ${r.leads} leads, ${r.viewings} viewings`);
});

// Media pipeline (D6): raw listing photos -> WebP variants + blurhash.
export const onListingPhoto = onObjectFinalized({ bucket: mediaBucketName(process.env), memory: '1GiB', timeoutSeconds: 120 }, async (event) => {
  const r = await handleListingUpload(getStorage().bucket(event.data.bucket), getFirestore(), event.data.name);
  if (r.status === 'rejected') console.warn(`rejected ${event.data.name}: ${r.reason}`);
});

// Search (D4): live listings mirrored into <TENANT_ID>_listings on Typesense.
// Deployed as search-onListingWrite only when the project has search set up
// (see search/config.ts); otherwise the group is empty and needs no secret.
const searchCfg = searchConfig(process.env);
export const search = searchCfg ? { onListingWrite: listingSearchTrigger(searchCfg) } : {};

function listingSearchTrigger(cfg: SearchConfig) {
  const apiKey = defineSecret('TYPESENSE_API_KEY');
  return onDocumentWritten({ document: 'listings/{id}', secrets: [apiKey] }, async (event) => {
    if (!searchRelevantChange(event.data?.before.data(), event.data?.after.data())) return;
    const client = new Typesense({
      nodes: [{ host: cfg.host, port: 443, protocol: 'https' }],
      apiKey: apiKey.value(),
      connectionTimeoutSeconds: 5,
    });
    await syncListing(client, cfg.tenantId, event.params.id, event.data?.after.data());
  });
}

export { verificationExpiry };
