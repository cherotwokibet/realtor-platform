import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { contrast } from './contrast.ts';
import { placeholderSvgs } from './create.ts';

// `tenant rebrand <new-id> <name> --from <demo-id> --primary <hex> [--accent <hex>]`
// (P8-s05): a prospect's name and colours on the demo tenant, for a sales
// meeting. It copies the demo (features, fonts, type scale), derives a full
// palette that passes the same contrast checks as `validate`, and draws
// placeholder art in the new colours. Nothing is provisioned; the demo apps
// run on their built-in demo data. Not for real tenants: use `create`.

const HEX = /^#[0-9a-fA-F]{6}$/;
const WHITE = '#FFFFFF';
const NEAR_BLACK = '#1B1B1B';

const parse = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const hex = (rgb: number[]) => '#' + rgb.map((c) => Math.round(Math.max(0, Math.min(255, c))).toString(16).padStart(2, '0')).join('').toUpperCase();

/** [a] mixed toward [b] by [t] (0 = a, 1 = b). */
export function mix(a: string, b: string, t: number): string {
  const [x, y] = [parse(a), parse(b)];
  return hex(x.map((c, i) => c + (y[i] - c) * t));
}

/** [color] darkened in steps until it reaches [min]:1 against [on]; the hue stays. */
export function darkenUntil(color: string, on: string, min: number): string {
  let c = color.toUpperCase();
  for (let i = 0; i < 40 && contrast(c, on) < min; i++) c = mix(c, '#000000', 0.06);
  return c;
}

export interface Palette {
  colors: Record<string, string>;
  /** What was adjusted for readability, to say out loud in the meeting. */
  notes: string[];
}

/** A tenant palette from a brand colour (and accent), over [base]'s neutrals. */
export function derivePalette(base: Record<string, string>, primaryIn: string, accentIn?: string): Palette {
  if (!HEX.test(primaryIn)) throw new Error(`--primary must be a colour like #0B5D1E (got "${primaryIn}")`);
  if (accentIn && !HEX.test(accentIn)) throw new Error(`--accent must be a colour like #F2A541 (got "${accentIn}")`);
  const notes: string[] = [];
  const surface = base.surface;

  // The brand colour carries buttons and links, so it must read on white with white text on it.
  // It must also read on its own soft tint (selected chips, highlights).
  const softOf = (p: string) => {
    const tint = mix(p, WHITE, 0.88);
    return contrast(p, tint) >= 4.5 ? tint : mix(p, WHITE, 0.95);
  };
  let primary = darkenUntil(primaryIn, surface, 4.5);
  let primarySoft = softOf(primary);
  for (let i = 0; i < 40 && contrast(primary, primarySoft) < 4.5; i++) {
    primary = mix(primary, '#000000', 0.04);
    primarySoft = softOf(primary);
  }
  if (primary !== primaryIn.toUpperCase()) notes.push(`primary ${primaryIn.toUpperCase()} → ${primary} so text on it and links stay readable`);
  const onPrimary = contrast(WHITE, primary) >= 4.5 ? WHITE : NEAR_BLACK;

  let accent = (accentIn ?? base.accent).toUpperCase();
  let onAccent = contrast(NEAR_BLACK, accent) >= contrast(WHITE, accent) ? NEAR_BLACK : WHITE;
  if (contrast(onAccent, accent) < 4.5) {
    accent = darkenUntil(accent, WHITE, 4.5);
    onAccent = WHITE;
    notes.push(`accent → ${accent} so its button text stays readable`);
  }
  const accentText = darkenUntil(accent, surface, 4.5);

  return { colors: { ...base, primary, onPrimary, primarySoft, accent, onAccent, accentText }, notes };
}

export interface RebrandOptions {
  primary: string;
  accent?: string;
  /** The demo tenant to copy (its id; no tenant is named in code). */
  from: string;
}

export function rebrandTenant(root: string, id: string, name: string, opts: RebrandOptions): { tenantFile: string; notes: string[] } {
  if (!/^[a-z][a-z0-9-]{2,23}$/.test(id)) throw new Error(`id must be 3-24 chars of a-z, 0-9 and "-", starting with a letter (got "${id}")`);
  if (name.trim().length < 2) throw new Error('name is required, e.g. "Acme Realty"');
  const tenantFile = join(root, 'tenants', `${id}.json`);
  const brandDir = join(root, 'brand', id);
  if (existsSync(tenantFile) || existsSync(brandDir)) throw new Error(`tenants/${id}.json or brand/${id}/ already exists`);

  const from = JSON.parse(readFileSync(join(root, 'tenants', `${opts.from}.json`), 'utf8'));
  const { colors, notes } = derivePalette(from.brand.colors, opts.primary, opts.accent);
  const flat = id.replace(/-/g, '');
  const domain = `${id}.example.com`;
  const logo = Object.fromEntries(Object.entries(from.brand.logo as Record<string, string>).map(([k, v]) => [k, v.replace(/^brand\/[^/]+\//, `brand/${id}/`)]));
  const tenant = {
    ...from,
    id,
    name: name.trim(),
    earbNo: 'TBC',
    brand: { ...from.brand, logo, appIcon: (from.brand.appIcon as string).replace(/^brand\/[^/]+\//, `brand/${id}/`), colors },
    domains: { share: domain, app: `app.${domain}`, admin: `admin.${domain}` },
    apps: { androidId: `com.example.${flat}`, iosId: `com.example.${flat}` },
    firebase: { ...from.firebase, projects: { dev: `${id}-dev`, stage: `${id}-stage`, prod: `${id}-prod` } },
    contact: { phone: 'TBC', whatsapp: 'TBC', email: `info@${domain}` },
  };
  delete (tenant as Record<string, unknown>).tagline;

  mkdirSync(brandDir, { recursive: true });
  for (const [f, svg] of Object.entries(placeholderSvgs(colors.primary, colors.accent, colors.onPrimary))) writeFileSync(join(brandDir, f), svg);
  writeFileSync(tenantFile, JSON.stringify(tenant, null, 2) + '\n');
  return { tenantFile, notes };
}
