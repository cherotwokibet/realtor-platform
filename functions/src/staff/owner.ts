/**
 * Makes the first owner of a project, once. The person signs in to the admin
 * first (so their account exists), then someone with access to the project
 * runs, with Application Default Credentials:
 *   PROJECT=<project-id> OWNER_EMAIL=<their email> npm --prefix functions run staff:owner
 * Refused once the project has an owner; from then on owners add staff in the admin.
 */
import { initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { bootstrapOwner } from '../api/staff';

async function main(): Promise<void> {
  const projectId = process.env.PROJECT;
  const email = process.env.OWNER_EMAIL;
  if (!projectId || !email) {
    console.error('set PROJECT=<project-id> and OWNER_EMAIL=<email of an account that has signed in once>');
    process.exit(1);
  }
  initializeApp({ projectId });
  const { uid } = await bootstrapOwner(getFirestore(), getAuth(), email);
  console.log(`✓ ${email} (${uid}) is the owner of ${projectId}; they get the role on their next sign-in`);
}

main().catch((e) => {
  console.error(`✗ ${(e as Error).message}`);
  process.exit(1);
});
