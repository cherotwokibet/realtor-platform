/**
 * Search (D4) is on for a project only when its functions/.env.<project-id>
 * (local, not committed) sets TENANT_ID and TYPESENSE_HOST, with the API key
 * in Secret Manager as TYPESENSE_API_KEY. Until then the search trigger is
 * not deployed at all, so a deploy needs no Typesense host or secret.
 */
export interface SearchConfig {
  tenantId: string;
  host: string;
}

export function searchConfig(env: Record<string, string | undefined>): SearchConfig | null {
  const tenantId = env.TENANT_ID?.trim();
  const host = env.TYPESENSE_HOST?.trim();
  if (!tenantId || !host) return null;
  if (!/^[a-z0-9][a-z0-9-]*$/.test(tenantId)) throw new Error(`TENANT_ID "${tenantId}" must be a tenant id (lowercase letters, digits, dashes)`);
  if (/[/:\s]/.test(host)) throw new Error(`TYPESENSE_HOST "${host}" must be a bare host name, e.g. xyz.a1.typesense.net`);
  return { tenantId, host };
}
