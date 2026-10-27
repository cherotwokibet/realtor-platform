/**
 * Where the seed may write. The emulator always; a real project only when
 * it is named in SEED_PROJECT and is a dev project (id ends in "-dev"), so
 * demo data can never reach stage or prod.
 */
export type SeedTarget = { projectId: string; emulator: boolean } | { error: string };

export function seedTarget(env: Record<string, string | undefined>): SeedTarget {
  if (env.FIRESTORE_EMULATOR_HOST) return { projectId: env.GCLOUD_PROJECT ?? 'demo-realtor', emulator: true };
  const project = env.SEED_PROJECT;
  if (!project) return { error: 'Set FIRESTORE_EMULATOR_HOST (emulator) or SEED_PROJECT=<id>-dev (a real dev project).' };
  if (!/^[a-z][a-z0-9-]{4,28}-dev$/.test(project)) return { error: `SEED_PROJECT=${project}: only dev projects (ids ending in -dev) can be seeded.` };
  return { projectId: project, emulator: false };
}
