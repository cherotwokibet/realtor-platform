/**
 * Cloud Functions entry point. Rule D7: anything about money, approval,
 * verification or commissions happens here, never in a client.
 *
 * Planned (see tracker):
 *   P2  onListingWrite  -> sync to Typesense, set slug/geohash, expiresAt
 *   P2  onMediaUpload   -> sharp/ffmpeg variants, watermark, blurhash (D6)
 *   P4  sendPush        -> FCM HTTP v1 (replaces the legacy server key)
 *   P6  mpesaStkPush / mpesaCallback -> Daraja
 *   P6  verifyListing / expireListings (scheduled, 30-day re-verification)
 */
import { setGlobalOptions } from 'firebase-functions/v2';
import { onRequest } from 'firebase-functions/v2/https';
import { REGION, verificationExpiry } from './listing-rules';

setGlobalOptions({ region: REGION, maxInstances: 10 });

export const health = onRequest((_req, res) => {
  res.json({ ok: true, project: process.env.GCLOUD_PROJECT ?? 'local', region: REGION });
});

export { verificationExpiry };
