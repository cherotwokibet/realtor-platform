import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

// `tenant create <id> <name>`: a valid starting tenant file and placeholder
// brand folder for a new realtor. Values to replace are marked TBC or
// example.com; nothing is provisioned (see infra/terraform).

const ID = /^[a-z][a-z0-9-]{2,23}$/; // leaves room for "-stage" in GCP project ids

/** Placeholder art: a house mark and plain bars where the name will go. No <text>. */
function placeholderSvgs(primary: string, accent: string, onDark: string): Record<string, string> {
  const mark = (fill: string, door: string) =>
    `<path fill="${fill}" d="M20 150 150 20l130 130h-34L150 54 54 150z"/><rect fill="${door}" x="126" y="92" width="48" height="58" rx="4"/>`;
  const bars = (fill: string, x: number, y: number, w: number) =>
    `<rect fill="${fill}" x="${x}" y="${y}" width="${w}" height="40" rx="8"/><rect fill="${fill}" opacity=".5" x="${x}" y="${y + 56}" width="${Math.round(w * 0.6)}" height="16" rx="8"/>`;
  const svg = (w: number, h: number, body: string) =>
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" role="img" aria-label="Placeholder logo"><title>Placeholder logo: replace with the realtor's artwork</title>${body}</svg>\n`;
  return {
    'mark.svg': svg(300, 160, mark(primary, accent)),
    'mark-reverse.svg': svg(300, 160, mark(onDark, accent)),
    'logo-horizontal.svg': svg(900, 160, mark(primary, accent) + bars(primary, 310, 50, 520)),
    'logo-horizontal-reverse.svg': svg(900, 160, mark(onDark, accent) + bars(onDark, 310, 50, 520)),
    'logo-stacked.svg': svg(600, 300, `<g transform="translate(150 0)">${mark(primary, accent)}</g>` + bars(primary, 100, 190, 400)),
    'logo-stacked-reverse.svg': svg(600, 300, `<g transform="translate(150 0)">${mark(onDark, accent)}</g>` + bars(onDark, 100, 190, 400)),
    'favicon.svg': svg(300, 300, `<rect width="300" height="300" rx="60" fill="${primary}"/><g transform="translate(0 70)">${mark(onDark, accent)}</g>`),
  };
}

export interface CreateResult {
  tenantFile: string;
  brandDir: string;
}

export function createTenant(root: string, id: string, name: string): CreateResult {
  if (!ID.test(id)) throw new Error(`id must be 3-24 chars of a-z, 0-9 and "-", starting with a letter (got "${id}")`);
  if (name.trim().length < 2) throw new Error('name is required, e.g. "Acme Realty Ltd"');
  const tenantFile = join(root, 'tenants', `${id}.json`);
  const brandDir = join(root, 'brand', id);
  if (existsSync(tenantFile) || existsSync(brandDir)) throw new Error(`tenants/${id}.json or brand/${id}/ already exists`);

  // A checked palette, type scale and radii; the realtor's brand replaces them before go-live.
  const base = JSON.parse(readFileSync(join(root, 'tenants', 'schema', 'starter.json'), 'utf8'));
  const c = base.brand.colors;
  const flat = id.replace(/-/g, '');
  const domain = `${id}.example.com`;
  const logo = (f: string) => `brand/${id}/${f}`;
  const tenant = {
    $schema: './schema/tenant.schema.json',
    schemaVersion: 1,
    id,
    name: name.trim(),
    earbNo: 'TBC',
    brand: {
      logo: {
        primary: logo('logo-stacked.svg'),
        onDark: logo('logo-stacked-reverse.svg'),
        horizontal: logo('logo-horizontal.svg'),
        horizontalOnDark: logo('logo-horizontal-reverse.svg'),
        mark: logo('mark.svg'),
        markOnDark: logo('mark-reverse.svg'),
        favicon: logo('favicon.svg'),
      },
      appIcon: logo('mark-reverse.svg'),
      colors: c,
      fonts: base.brand.fonts,
      typeScale: base.brand.typeScale,
      radius: base.brand.radius,
      spacingBase: base.brand.spacingBase,
    },
    domains: { share: domain, app: `app.${domain}`, admin: `admin.${domain}` },
    apps: { androidId: `com.example.${flat}`, iosId: `com.example.${flat}` },
    firebase: { projects: { dev: `${id}-dev`, stage: `${id}-stage`, prod: `${id}-prod` }, region: base.region },
    contact: { phone: 'TBC', whatsapp: 'TBC', email: `info@${domain}` },
    locale: { default: 'en-KE', extra: ['sw'], currency: 'KES' },
    features: { sale: true, rent: true, shortStay: false, offPlan: false, mpesa: false, ads: false, aiSearch: false, chat: false },
    mpesa: { shortcode: 'secret://mpesa-shortcode', type: 'paybill' },
  };

  mkdirSync(brandDir, { recursive: true });
  for (const [f, svg] of Object.entries(placeholderSvgs(c.primary, c.accent, c.onPrimary))) writeFileSync(join(brandDir, f), svg);
  writeFileSync(tenantFile, JSON.stringify(tenant, null, 2) + '\n');
  return { tenantFile, brandDir };
}
