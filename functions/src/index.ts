/**
 * Cloud Functions entry point. Rule D7: anything about money, approval,
 * verification or commissions happens here, never in a client.
 *
 * Callables: createLead, logContactTap, bookViewing, submitReview, logRecommendation (App Check, D16; share* twins for the share pages), openSlots, updateViewingStatus, rescheduleViewing, addAgentBlock, removeAgentBlock, updateLeadStage, submitListing, moderateListing, confirmListing, featureListing, setHotListing, setPlacement, moderateEdit, importListings, saveAgent, monthlyReport, saveArea, moderateReview, submitListingReview, savePage, saveProject, setStaffRole, saveStaffProfile, dataRequest, saveMyProfile, deleteMyAccount.
 * Scheduled, every 5 minutes: savedSearchAlerts (D18, inbox + push). Nightly: areaStats (P3-s05), purgeExpiredLeads (D12 retention), expireListings (P6-s02 verification), agentResponseTimes (P5-s03).
 *
 * Planned (see tracker):
 *   P4  sendPush        -> FCM HTTP v1 (replaces the legacy server key)
 *   P6  mpesaStkPush / mpesaCallback -> Daraja
 */
import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
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
import { AGENT_PHOTO_PATH, handleAgentPhoto, handleListingUpload, refuseVideo, UPLOAD_PATH, VIDEO_EXT } from './media/upload';
import { startTranscode } from './media/transcode';
import { callerFrom } from './api/auth';
import * as ads from './api/ads';
import * as support from './api/support';
import * as leads from './api/leads';
import * as listings from './api/listings';
import * as staff from './api/staff';
import * as viewings from './api/viewings';
import * as availability from './api/availability';
import * as agents from './api/agents';
import * as reports from './api/reports';
import * as areas from './api/areas';
import * as reviews from './api/reviews';
import * as pages from './api/pages';
import * as projects from './api/projects';
import * as recommendations from './api/recommendations';
import { refreshAreaStats } from './api/areas';
import { INDEX_CACHE, listingIndex as buildListingIndex } from './api/listing-index';
import { fcmSender, sweepSavedSearches } from './api/alerts';
import { dataRequest as runDataRequest } from './api/privacy';
import { type CustomerAuth, deleteAccount, saveProfile } from './api/profile';
import { purgeExpired } from './api/retention';
import { callableTwin, enforced, logAppCheck, type PublicCallable, sharePagesInvoker } from './api/appcheck';
import { updateAgentResponseTimes } from './api/response';
import { REGION, verificationExpiry } from './listing-rules';
import { callbackUrl, type MpesaConfig, mpesaConfig } from './payments/config';
import { parseStkCallback } from './payments/daraja';
import { type PaymentDeps, reconcilePayments, recordStkCallback, startViewingPayment } from './payments/payments';

initializeApp();

setGlobalOptions({ region: REGION, maxInstances: 10 });

export const health = onRequest((_req, res) => {
  res.json({ ok: true, project: process.env.GCLOUD_PROJECT ?? 'local', region: REGION });
});

// Callable API (P2-s03). Inputs are zod-validated in ./api; the clients
// never write these collections directly (see firestore.rules).
// The three public ones are App Check guarded (D16): watched, and enforced
// per Function once ENFORCE_APP_CHECK lists it.
const publicCalls: Record<PublicCallable, (data: unknown) => Promise<unknown>> = {
  createLead: (data) => leads.createLead(getFirestore(), data),
  logContactTap: (data) => leads.logContactTap(getFirestore(), data),
  bookViewing: (data) => viewings.bookViewing(getFirestore(), data),
  submitReview: (data) => reviews.submitReview(getFirestore(), data),
  logRecommendation: (data) => recommendations.logRecommendation(getFirestore(), data),
  submitFeedback: (data) => support.submitFeedback(getFirestore(), data),
};
const enforce = enforced(process.env);
const publicCallable = (fn: PublicCallable) =>
  onCall({ enforceAppCheck: enforce.has(fn) }, (req) => {
    logAppCheck(fn, req.app !== undefined);
    return publicCalls[fn](req.data);
  });
export const createLead = publicCallable('createLead');
export const logContactTap = publicCallable('logContactTap');
export const bookViewing = publicCallable('bookViewing');

// Their twins for the share pages' server, which cannot attest: only the
// share-pages service account may invoke them (Cloud Run IAM).
const twin = (fn: PublicCallable) =>
  onRequest({ invoker: sharePagesInvoker(process.env.GCLOUD_PROJECT ?? 'local') }, callableTwin(publicCalls[fn]));
export const shareCreateLead = twin('createLead');
export const shareLogContactTap = twin('logContactTap');
export const shareBookViewing = twin('bookViewing');
export const submitReview = publicCallable('submitReview');
export const shareSubmitReview = twin('submitReview');
// Similar-homes click-through (P7-s04): counts only.
export const logRecommendation = publicCallable('logRecommendation');
// Help & feedback from the site (support inbox).
export const submitFeedback = publicCallable('submitFeedback');
export const shareSubmitFeedback = twin('submitFeedback');
export const updateFeedback = onCall((req) => support.updateFeedback(getFirestore(), callerFrom(req.auth), req.data));
export const saveAd = onCall((req) => ads.saveAd(getFirestore(), callerFrom(req.auth), req.data));
export const deleteAd = onCall((req) => ads.deleteAd(getFirestore(), callerFrom(req.auth), req.data));
export const shareLogRecommendation = twin('logRecommendation');
// Public, read-only: which times a listing's agent can still take on a day (P4-s04).
export const openSlots = onCall((req) => viewings.openSlots(getFirestore(), req.data));
export const updateViewingStatus = onCall((req) => viewings.updateViewingStatus(getFirestore(), callerFrom(req.auth), req.data));
export const rescheduleViewing = onCall((req) => viewings.rescheduleViewing(getFirestore(), callerFrom(req.auth), req.data));
export const addAgentBlock = onCall((req) => availability.addAgentBlock(getFirestore(), callerFrom(req.auth), req.data));
export const removeAgentBlock = onCall((req) => availability.removeAgentBlock(getFirestore(), callerFrom(req.auth), req.data));
export const updateLeadStage = onCall((req) => leads.updateLeadStage(getFirestore(), callerFrom(req.auth), req.data));
export const submitListing = onCall((req) => listings.submitListing(getFirestore(), callerFrom(req.auth), req.data));
export const moderateListing = onCall((req) => listings.moderateListing(getFirestore(), callerFrom(req.auth), req.data));
export const confirmListing = onCall((req) => listings.confirmListing(getFirestore(), callerFrom(req.auth), req.data));
export const featureListing = onCall((req) => listings.featureListing(getFirestore(), callerFrom(req.auth), req.data));
export const setHotListing = onCall((req) => listings.setHotListing(getFirestore(), callerFrom(req.auth), req.data));
export const setPlacement = onCall((req) => listings.setPlacement(getFirestore(), callerFrom(req.auth), req.data));
export const moderateEdit = onCall((req) => listings.moderateEdit(getFirestore(), callerFrom(req.auth), req.data));
export const importListings = onCall({ timeoutSeconds: 120 }, (req) => listings.importListings(getFirestore(), callerFrom(req.auth), req.data));
export const saveAgent = onCall((req) => agents.saveAgent(getFirestore(), callerFrom(req.auth), req.data));
export const monthlyReport = onCall((req) => reports.monthlyReport(getFirestore(), callerFrom(req.auth), req.data));
export const saveArea = onCall((req) => areas.saveArea(getFirestore(), callerFrom(req.auth), req.data));
export const moderateReview = onCall((req) => reviews.moderateReview(getFirestore(), callerFrom(req.auth), req.data));
export const submitListingReview = onCall((req) => reviews.submitListingReview(getFirestore(), callerFrom(req.auth), req.data));
export const saveProject = onCall((req) => projects.saveProject(getFirestore(), callerFrom(req.auth), req.data));
export const savePage = onCall((req) => pages.savePage(getFirestore(), callerFrom(req.auth), req.data));
export const setStaffRole = onCall((req) => staff.setStaffRole(getFirestore(), getAuth(), callerFrom(req.auth), req.data));
export const saveStaffProfile = onCall((req) => staff.saveStaffProfile(getFirestore(), getAuth(), callerFrom(req.auth), req.data));
export const dataRequest = onCall((req) => runDataRequest(getFirestore(), callerFrom(req.auth), req.data));

// The customer's own profile and account (My account > Edit Profile).
const customerAuth: CustomerAuth = {
  setName: async (uid, name) => {
    await getAuth().updateUser(uid, { displayName: name });
  },
  deleteUser: (uid) => getAuth().deleteUser(uid),
};
export const saveMyProfile = onCall((req) => saveProfile(getFirestore(), customerAuth, callerFrom(req.auth), req.data));
export const deleteMyAccount = onCall((req) => deleteAccount(getFirestore(), customerAuth, callerFrom(req.auth)));

// Saved-search alerts (D18, P4-s03): every 5 minutes, new live listings to
// matching inboxes, so an alert lands within 5 minutes of a listing going live.
// A quiet run is one small read (config/alerts) and one empty query. Phones
// that turned alerts on also get a push (FCM, no key needed on Android).
// The live homes as one small, CDN-cached file (P3-s01): Hosting serves it
// at /api/listings.json (firebase.json) and the app's index.html preloads it.
export const listingIndex = onRequest({ memory: '512MiB' }, async (req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).end();
    return;
  }
  res.set('Cache-Control', INDEX_CACHE);
  res.json(await buildListingIndex(getFirestore()));
});

export const savedSearchAlerts = onSchedule({ schedule: 'every 5 minutes', timeZone: 'Africa/Nairobi', retryCount: 1 }, async () => {
  const r = await sweepSavedSearches(getFirestore(), new Date(), fcmSender(getMessaging()));
  console.log(`alerts: ${r.listings} new listings, ${r.alerts} alerts, ${r.pushed} pushes`);
});

// Area guides (P3-s05): every night, each area's live listings and median rent.
export const areaStats = onSchedule({ schedule: '0 4 * * *', timeZone: 'Africa/Nairobi', retryCount: 1 }, async () => {
  const r = await refreshAreaStats(getFirestore());
  console.log(`area stats: ${r.areas} areas refreshed`);
});

// Retention (D12): every night, delete leads and viewings past their date.
// Only counts are logged, never what was deleted.
export const purgeExpiredLeads = onSchedule({ schedule: '15 3 * * *', timeZone: 'Africa/Nairobi', retryCount: 1 }, async () => {
  const r = await purgeExpired(getFirestore(), new Date());
  console.log(`retention: deleted ${r.leads} leads, ${r.viewings} viewings, ${r.blocks} ended time-off blocks`);
});

// Verification (P6-s02): every night, live listings not re-confirmed within
// 30 days lose the Verified badge and leave search (status expired).
export const expireListings = onSchedule({ schedule: '45 2 * * *', timeZone: 'Africa/Nairobi', retryCount: 1 }, async () => {
  const now = new Date();
  console.log(`verification: expired ${await listings.expireListings(getFirestore(), now)} listings`);
  console.log(`featured: ${await listings.clearLapsedFeatures(getFirestore(), now)} listings back to normal`);
});

// Response times (P5-s03): every night, each agent's typical reply time.
export const agentResponseTimes = onSchedule({ schedule: '30 3 * * *', timeZone: 'Africa/Nairobi', retryCount: 1 }, async () => {
  await updateAgentResponseTimes(getFirestore(), new Date());
});

// Media pipeline (D6): raw listing photos -> WebP variants + blurhash.
export const onListingPhoto = onObjectFinalized({ bucket: mediaBucketName(process.env), memory: '1GiB', timeoutSeconds: 120 }, async (event) => {
  const bucket = getStorage().bucket(event.data.bucket);
  const r = AGENT_PHOTO_PATH.test(event.data.name)
    ? await handleAgentPhoto(bucket, getFirestore(), event.data.name)
    : await handleListingUpload(bucket, getFirestore(), event.data.name);
  if (r.status === 'rejected') console.warn(`rejected ${event.data.name}: ${r.reason}`);
});

// Same paths, video files (D15): the Cloud Run job transcode-video makes
// the HLS ladder and poster; this only starts it for the uploaded object.
export const onListingVideo = onObjectFinalized({ bucket: mediaBucketName(process.env) }, async (event) => {
  const path = event.data.name;
  if (!UPLOAD_PATH.test(path) || !VIDEO_EXT.test(path)) return;
  const token = async () => (await applicationDefault().getAccessToken()).access_token;
  const started = await startTranscode(path, { project: process.env.GCLOUD_PROJECT ?? '', region: REGION, token });
  if (started === 'no-job') {
    await refuseVideo(getStorage().bucket(event.data.bucket), getFirestore(), path, 'videos are not switched on for this site yet');
  }
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

// M-Pesa (P6-s01): deployed as payments-* only when the project has M-Pesa
// set up (see payments/config.ts); otherwise the group is empty.
const mpesaCfg = mpesaConfig(process.env);
export const payments = mpesaCfg ? paymentFunctions(mpesaCfg) : {};

function paymentFunctions(cfg: MpesaConfig) {
  const key = defineSecret('MPESA_CONSUMER_KEY');
  const secret = defineSecret('MPESA_CONSUMER_SECRET');
  const passkey = defineSecret('MPESA_PASSKEY');
  const secrets = [key, secret, passkey];
  const deps = (): PaymentDeps => ({
    daraja: { ...cfg, consumerKey: key.value(), consumerSecret: secret.value(), passkey: passkey.value() },
    callbackUrl: callbackUrl(process.env.GCLOUD_PROJECT ?? '', REGION),
  });
  return {
    startViewingPayment: onCall({ secrets }, (req) => startViewingPayment(getFirestore(), req.data, deps())),
    // The share pages' twin (D16): only their service account may invoke it.
    shareStartViewingPayment: onRequest(
      { secrets, invoker: sharePagesInvoker(process.env.GCLOUD_PROJECT ?? 'local') },
      callableTwin((data) => startViewingPayment(getFirestore(), data, deps())),
    ),
    // Safaricom posts here; always 200 so it does not retry, details only in our logs.
    mpesaCallback: onRequest({ secrets: [] }, async (req, res) => {
      const t = typeof req.query.t === 'string' ? req.query.t : undefined;
      const r = await recordStkCallback(getFirestore(), req.method === 'POST' ? parseStkCallback(req.body) : null, t);
      if (r === 'ignored') console.warn('mpesaCallback: ignored a callback (unknown push or wrong token)');
      res.json({ ResultCode: 0, ResultDesc: 'Accepted' });
    }),
    reconcilePayments: onSchedule({ schedule: 'every 5 minutes', timeZone: 'Africa/Nairobi', retryCount: 0, secrets }, async () => {
      const r = await reconcilePayments(getFirestore(), deps());
      if (r.checked) console.log(`payments: ${r.checked} pending checked, ${r.settled} settled`);
    }),
  };
}

export { verificationExpiry };
