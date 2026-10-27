/**
 * Cloud Functions entry point. Rule D7: anything about money, approval,
 * verification or commissions happens here, never in a client.
 *
 * Callables: createLead, logContactTap, updateLeadStage, submitListing, moderateListing.
 *
 * Planned (see tracker):
 *   P4  sendPush        -> FCM HTTP v1 (replaces the legacy server key)
 *   P6  mpesaStkPush / mpesaCallback -> Daraja
 *   P6  verifyListing / expireListings (scheduled, 30-day re-verification)
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall, onRequest } from 'firebase-functions/v2/https';
import { onObjectFinalized } from 'firebase-functions/v2/storage';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { defineSecret, defineString } from 'firebase-functions/params';
import { Client as Typesense } from 'typesense';
import { searchRelevantChange, syncListing } from './search/sync';
import { getStorage } from 'firebase-admin/storage';
import { handleListingUpload, handleListingVideo } from './media/upload';
import { callerFrom } from './api/auth';
import * as leads from './api/leads';
import * as listings from './api/listings';
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
export const updateLeadStage = onCall((req) => leads.updateLeadStage(getFirestore(), callerFrom(req.auth), req.data));
export const submitListing = onCall((req) => listings.submitListing(getFirestore(), callerFrom(req.auth), req.data));
export const moderateListing = onCall((req) => listings.moderateListing(getFirestore(), callerFrom(req.auth), req.data));

// Media pipeline (D6): raw listing photos -> WebP variants + blurhash.
export const onListingPhoto = onObjectFinalized({ memory: '1GiB', timeoutSeconds: 120 }, async (event) => {
  const r = await handleListingUpload(getStorage().bucket(event.data.bucket), getFirestore(), event.data.name);
  if (r.status === 'rejected') console.warn(`rejected ${event.data.name}: ${r.reason}`);
});

// Same paths, video files: ffmpeg -> HLS ladder + poster. Needs an ffmpeg
// binary at FFMPEG_PATH (or on PATH); see docs/decisions.md D14.
export const onListingVideo = onObjectFinalized({ memory: '2GiB', cpu: 2, timeoutSeconds: 540 }, async (event) => {
  const r = await handleListingVideo(getStorage().bucket(event.data.bucket), getFirestore(), event.data.name);
  if (r.status === 'rejected') console.warn(`rejected ${event.data.name}: ${r.reason}`);
});

// Search (D4): live listings mirrored into <TENANT_ID>_listings on Typesense.
const TENANT_ID = defineString('TENANT_ID');
const TYPESENSE_HOST = defineString('TYPESENSE_HOST');
const TYPESENSE_API_KEY = defineSecret('TYPESENSE_API_KEY');

export const onListingWrite = onDocumentWritten({ document: 'listings/{id}', secrets: [TYPESENSE_API_KEY] }, async (event) => {
  if (!searchRelevantChange(event.data?.before.data(), event.data?.after.data())) return;
  const client = new Typesense({
    nodes: [{ host: TYPESENSE_HOST.value(), port: 443, protocol: 'https' }],
    apiKey: TYPESENSE_API_KEY.value(),
    connectionTimeoutSeconds: 5,
  });
  await syncListing(client, TENANT_ID.value(), event.params.id, event.data?.after.data());
});

export { verificationExpiry };
