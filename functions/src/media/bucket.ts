/**
 * The bucket listing photos go into: Terraform makes one per project,
 * "<project-id>-media" (infra/terraform/modules/firebase-env). Projects have
 * no default Firebase bucket, so the trigger must name this one.
 */
export function mediaBucketName(env: Record<string, string | undefined>): string {
  let project = env.GCLOUD_PROJECT?.trim();
  if (!project && env.FIREBASE_CONFIG) {
    try {
      project = (JSON.parse(env.FIREBASE_CONFIG) as { projectId?: string }).projectId;
    } catch {
      // Not JSON: fall through to the error below.
    }
  }
  if (!project) throw new Error('Cannot tell the project id (GCLOUD_PROJECT / FIREBASE_CONFIG unset), so the media bucket is unknown');
  return `${project}-media`;
}
