import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, cpSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { generateIcons, recolourSvg, writeHomeImages } from '../src/icons.ts';
import { repoRoot } from '../src/validate.ts';

test('recolourSvg sets every fill', () => {
  const out = recolourSvg('<path fill="#5E0202"/><path fill="#D1992A"/>', '#FFFFFF');
  assert.equal(out, '<path fill="#FFFFFF"/><path fill="#FFFFFF"/>');
});

for (const id of ['realtime-estates', 'demo-homes']) {
  test(`icons for ${id} have the platform sizes`, async () => {
    // Work on a copy so the test never touches the real brand folder.
    const root = mkdtempSync(join(tmpdir(), 'icons-'));
    mkdirSync(join(root, 'brand'));
    cpSync(join(repoRoot(), 'brand', id), join(root, 'brand', id), { recursive: true });
    const t = JSON.parse(readFileSync(join(repoRoot(), 'tenants', `${id}.json`), 'utf8'));
    const { outDir, files } = await generateIcons(root, t);

    const size = async (f: string) => {
      const m = await sharp(join(outDir, f)).metadata();
      return [m.width, m.height, m.hasAlpha];
    };
    assert.deepEqual((await size('app-icon-1024.png')).slice(0, 2), [1024, 1024]);
    assert.deepEqual((await size('play-icon-512.png')).slice(0, 2), [512, 512]);
    assert.deepEqual((await size('android-foreground-432.png')).slice(0, 2), [432, 432]);
    assert.deepEqual((await size('splash-1152.png')).slice(0, 2), [1152, 1152]);
    assert.deepEqual((await size('android-notification-96.png')).slice(0, 2), [96, 96]);
    assert.deepEqual((await size('splash-branding-800x320.png')).slice(0, 2), [800, 320]);
    assert.deepEqual((await size('og-default-1200x630.png')).slice(0, 2), [1200, 630]);
    assert.ok(files.includes('favicon-16.png'));

    // App Store icons must be opaque: corner pixel equals the tenant primary colour.
    const { data } = await sharp(join(outDir, 'app-icon-1024.png')).removeAlpha().raw().toBuffer({ resolveWithObject: true });
    const hex = '#' + [data[0], data[1], data[2]].map((v) => v.toString(16).padStart(2, '0')).join('').toUpperCase();
    assert.equal(hex, t.brand.colors.primary);

    // Adaptive foreground keeps the 18 dp border clear (outer 1/6 of the canvas is transparent).
    const fg = await sharp(join(outDir, 'android-foreground-432.png')).raw().toBuffer({ resolveWithObject: true });
    const border = 72; // 18/108 * 432
    let opaqueInBorder = 0;
    for (let y = 0; y < 432; y++) for (let x = 0; x < 432; x++) {
      if (x >= border && x < 432 - border && y >= border && y < 432 - border) continue;
      if (fg.data[(y * 432 + x) * 4 + 3] > 0) opaqueInBorder++;
    }
    assert.equal(opaqueInBorder, 0);
  });
}

test('home page photos are resized to WebP under fixed, numbered names; none named, none written', async () => {
  const root = mkdtempSync(join(tmpdir(), 'home-'));
  mkdirSync(join(root, 'brand', 'x', 'home'), { recursive: true });
  for (const f of ['hero.jpg', 'b1.jpg', 'b2.jpg']) {
    await sharp({ create: { width: 3000, height: 1200, channels: 3, background: { r: 30, g: 60, b: 90 } } }).jpeg().toFile(join(root, 'brand/x/home', f));
  }
  const out = mkdtempSync(join(tmpdir(), 'home-out-'));
  const tenant = { home: { hero: { title: 't', image: 'brand/x/home/hero.jpg' }, banner: { title: 'b', images: ['brand/x/home/b1.jpg', 'brand/x/home/b2.jpg'] } } };
  assert.deepEqual(await writeHomeImages(root, tenant, out), ['home-hero-1.webp', 'home-banner-1.webp', 'home-banner-2.webp']);
  const meta = await sharp(join(out, 'home-hero-1.webp')).metadata();
  assert.equal(meta.format, 'webp');
  assert.equal(meta.width, 1600);
  assert.deepEqual(await writeHomeImages(root, {}, out), []);
});
