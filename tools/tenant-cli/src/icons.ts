// Generates every raster brand asset a realtor needs from the vector files in
// their tenant config. Output: brand/<id>/generated/ (gitignored, rebuilt by
// `prepare` and CI). Sizes follow the platform specs noted beside each file.
import { readFileSync, mkdirSync, writeFileSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';
import sharp from 'sharp';

type Rgba = { r: number; g: number; b: number; alpha: number };
const CLEAR: Rgba = { r: 0, g: 0, b: 0, alpha: 0 };

function hexToRgba(hex: string): Rgba {
  const v = hex.replace('#', '');
  return { r: parseInt(v.slice(0, 2), 16), g: parseInt(v.slice(2, 4), 16), b: parseInt(v.slice(4, 6), 16), alpha: 1 };
}

/** Every fill in the SVG set to one colour: monochrome and tinted icons. */
export function recolourSvg(svg: string, hex: string): string {
  return svg.replace(/fill="#[0-9A-Fa-f]{3,8}"/g, `fill="${hex}"`);
}

function viewBoxWidth(svg: string): number {
  const m = svg.match(/viewBox="[-\d.]+ [-\d.]+ ([\d.]+) [\d.]+"/);
  return m ? parseFloat(m[1]) : 1000;
}

/** Rasterise an SVG to a given width (height follows the aspect ratio). */
async function raster(svg: string, width: number): Promise<Buffer> {
  const density = Math.min(2400, Math.max(72, (72 * width * 1.5) / viewBoxWidth(svg)));
  return sharp(Buffer.from(svg), { density }).resize({ width: Math.round(width) }).png().toBuffer();
}

/** Glyph centred on a square canvas. `scale` = glyph width / canvas width. */
async function iconOn(svg: string, size: number, scale: number, bg: Rgba, dy = 0): Promise<Buffer> {
  const glyph = await raster(svg, size * scale);
  const meta = await sharp(glyph).metadata();
  return sharp({ create: { width: size, height: size, channels: 4, background: bg } })
    .composite([{
      input: glyph,
      left: Math.round((size - meta.width!) / 2),
      top: Math.round((size - meta.height!) / 2 + dy * size),
    }])
    .png()
    .toBuffer();
}

/** Artwork fitted inside a w×h box with padding, on a background. */
async function fitted(svg: string, w: number, h: number, pad: number, bg: Rgba): Promise<Buffer> {
  const art = await sharp(Buffer.from(svg), { density: 600 })
    .resize({ width: Math.round(w * (1 - 2 * pad)), height: Math.round(h * (1 - 2 * pad)), fit: 'inside' })
    .png()
    .toBuffer();
  return sharp({ create: { width: w, height: h, channels: 4, background: bg } })
    .composite([{ input: art, gravity: 'center' }])
    .png()
    .toBuffer();
}

export interface IconReport { outDir: string; files: string[] }

export async function generateIcons(root: string, tenant: any): Promise<IconReport> {
  const b = tenant.brand;
  const read = (p: string) => readFileSync(join(root, p), 'utf8');
  const glyph = read(b.appIcon); // reverse mark: drawn on the primary colour
  const mark = read(b.logo.mark);
  const primary = hexToRgba(b.colors.primary);
  const onPrimary: string = b.colors.onPrimary;
  const outDir = join(root, 'brand', tenant.id, 'generated');
  mkdirSync(outDir, { recursive: true });
  const files: string[] = [];
  const put = async (name: string, buf: Buffer | Promise<Buffer>) => {
    writeFileSync(join(outDir, name), await buf);
    files.push(name);
  };

  // iOS / App Store: 1024 opaque, full bleed. The system applies the mask.
  await put('app-icon-1024.png', sharp(await iconOn(glyph, 1024, 0.78, primary)).flatten({ background: primary }).png().toBuffer());
  // iOS 18+ dark (transparent background) and tinted (grayscale) variants.
  await put('ios-dark-1024.png', iconOn(glyph, 1024, 0.78, CLEAR));
  await put('ios-tinted-1024.png', sharp(await iconOn(recolourSvg(glyph, '#FFFFFF'), 1024, 0.78, CLEAR)).grayscale().png().toBuffer());
  // Google Play listing: 512 px, opaque square; Play rounds corners itself.
  await put('play-icon-512.png', sharp(await iconOn(glyph, 512, 0.78, primary)).flatten({ background: primary }).png().toBuffer());
  // Android adaptive: 108 dp layers (432 px = xxxhdpi), art inside the 66 dp safe zone.
  // A wide glyph at 56% width keeps its corners inside the 33 dp radius circle.
  await put('android-foreground-432.png', iconOn(glyph, 432, 0.56, CLEAR));
  await put('android-monochrome-432.png', iconOn(recolourSvg(glyph, '#FFFFFF'), 432, 0.56, CLEAR));
  // Android status-bar icon for push alerts: white on clear, 24 dp at xxxhdpi.
  await put('android-notification-96.png', iconOn(recolourSvg(glyph, '#FFFFFF'), 96, 0.84, CLEAR));
  // PWA maskable: opaque, art within the 40%-radius safe circle.
  await put('maskable-512.png', sharp(await iconOn(glyph, 512, 0.62, primary)).flatten({ background: primary }).png().toBuffer());
  await put('pwa-192.png', sharp(await iconOn(glyph, 192, 0.78, primary)).flatten({ background: primary }).png().toBuffer());
  await put('pwa-512.png', sharp(await iconOn(glyph, 512, 0.78, primary)).flatten({ background: primary }).png().toBuffer());
  await put('apple-touch-icon-180.png', sharp(await iconOn(glyph, 180, 0.78, primary)).flatten({ background: primary }).png().toBuffer());
  // Favicons from the simplified square symbol.
  const fav = read(b.logo.favicon);
  for (const s of [16, 32, 48]) await put(`favicon-${s}.png`, sharp(Buffer.from(fav), { density: 300 }).resize(s, s).png().toBuffer());
  copyFileSync(join(root, b.logo.favicon), join(outDir, 'favicon.svg'));
  files.push('favicon.svg');
  // Android 12+ splash: 1152 px, no icon background, art inside the 768 px circle.
  await put('splash-1152.png', iconOn(glyph, 1152, 0.6, CLEAR));
  await put('splash-branding-800x320.png', fitted(read(b.logo.horizontalOnDark), 800, 320, 0.12, CLEAR));
  // In-app logos (PNG so the app needs no SVG package). 3x for crisp phones.
  await put('logo-horizontal.png', raster(read(b.logo.horizontal), 1200));
  await put('logo-horizontal-reverse.png', raster(read(b.logo.horizontalOnDark), 1200));
  await put('logo-stacked.png', raster(read(b.logo.primary), 1200));
  await put('mark.png', raster(mark, 512));
  // Default WhatsApp / Open Graph preview (1200x630) for pages without a photo.
  await put('og-default-1200x630.png', sharp(await fitted(read(b.logo.onDark), 1200, 630, 0.16, primary)).flatten({ background: primary }).png().toBuffer());

  writeFileSync(join(outDir, 'README.txt'),
    `Generated by "tenant icons ${tenant.id}". Do not edit; change the SVGs in brand/${tenant.id}/ and the colours in tenants/${tenant.id}.json.\n` +
    `Splash window colour: ${b.colors.primary}. Monochrome icon colour is set by the launcher. onPrimary: ${onPrimary}.\n`);
  return { outDir, files };
}

/** Home page photo bands (tenant file `home`), under fixed names the app knows. */
export const HOME_BANDS = { hero: 'home-hero.webp', banner: 'home-banner.webp' } as const;

/**
 * The tenant's home page photos, resized for the web (1600 px wide at most,
 * WebP), into [outDir]. Returns the files written; none when the tenant
 * names no photos, and the app then draws the bands in the brand colour.
 */
export async function writeHomeImages(root: string, tenant: any, outDir: string): Promise<string[]> {
  const written: string[] = [];
  for (const [band, file] of Object.entries(HOME_BANDS)) {
    const src: string | undefined = tenant.home?.[band]?.image;
    if (!src) continue;
    await sharp(join(root, src)).rotate().resize({ width: 1600, withoutEnlargement: true }).webp({ quality: 72 }).toFile(join(outDir, file));
    written.push(file);
  }
  return written;
}
