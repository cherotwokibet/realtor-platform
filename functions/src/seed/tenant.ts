/**
 * config/tenant: the tenant's feature switches as a public doc, so Functions
 * read the same switches as the apps (D17). Only `id` and `features` are
 * copied from tenants/<id>.json; nothing else in that file is published here.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const TENANT_ID = /^[a-z][a-z0-9-]{1,40}$/;

/**
 * The tenant to seed: SEED_TENANT, else the first tenant file by name (no
 * tenant id is written in code, so a new realtor needs no change here).
 */
export function seedTenantId(env: Record<string, string | undefined>, repoRoot: string): string {
  const id = env.SEED_TENANT?.trim() || tenantIds(repoRoot)[0];
  if (!id || !TENANT_ID.test(id)) throw new Error(`SEED_TENANT=${id}: not a tenant id`);
  return id;
}

function tenantIds(repoRoot: string): string[] {
  return readdirSync(join(repoRoot, 'tenants'))
    .filter((f) => f.endsWith('.json'))
    .map((f) => f.slice(0, -'.json'.length))
    .sort();
}

export type TenantConfigDoc = { id: string; features: Record<string, boolean> };

/** `{ id, features }` from tenants/<id>.json under [repoRoot]. */
export function tenantConfigDoc(repoRoot: string, id: string): TenantConfigDoc {
  const file = JSON.parse(readFileSync(join(repoRoot, 'tenants', `${id}.json`), 'utf8')) as Record<string, unknown>;
  if (file.id !== id) throw new Error(`tenants/${id}.json has id ${String(file.id)}`);
  const f = file.features;
  if (!f || typeof f !== 'object' || Object.values(f).some((v) => typeof v !== 'boolean'))
    throw new Error(`tenants/${id}.json: features must be on/off switches`);
  return { id, features: f as Record<string, boolean> };
}
