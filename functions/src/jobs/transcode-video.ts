/**
 * Entry point of the Cloud Run job `transcode-video` (D15). OBJECT is the
 * uploaded video's path in the media bucket, set per execution by
 * onListingVideo; GCLOUD_PROJECT is set by Terraform. A rejected or ignored
 * video still exits 0: the reason is on the listing, and a retry would not
 * change it.
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { mediaBucketName } from '../media/bucket';
import { handleListingVideo } from '../media/upload';

async function main(): Promise<void> {
  const object = process.env.OBJECT;
  if (!object) throw new Error('OBJECT is not set');
  initializeApp();
  const r = await handleListingVideo(getStorage().bucket(mediaBucketName(process.env)), getFirestore(), object);
  // Paths only, never personal data.
  console.log(`${r.status} ${object}${r.status === 'rejected' ? `: ${r.reason}` : ''}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
