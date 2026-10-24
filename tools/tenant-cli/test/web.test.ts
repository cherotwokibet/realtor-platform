import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { patchIndexHtml, patchManifest, webDescription } from '../src/web.ts';
import { repoRoot } from '../src/validate.ts';

const tenant = (id: string) => JSON.parse(readFileSync(join(repoRoot(), 'tenants', `${id}.json`), 'utf8'));

// What `flutter create --platforms=web` writes (trimmed).
const flutterIndex = `<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <meta name="description" content="A new Flutter project.">
  <meta name="apple-mobile-web-app-title" content="realtor_app">
  <title>realtor_app</title>
  <link rel="manifest" href="manifest.json">
</head>
<body></body>
</html>`;

test('index.html carries the tenant, not the Flutter defaults', () => {
  const t = tenant('demo-homes');
  const out = patchIndexHtml(flutterIndex, t);
  assert.doesNotMatch(out, /A new Flutter project|realtor_app/);
  assert.match(out, /<html lang="en">/);
  assert.match(out, /<title>Demo Homes<\/title>/);
  assert.match(out, new RegExp(`<meta name="theme-color" content="${t.brand.colors.primary}">`));
  assert.match(out, /<meta property="og:image" content="og.png">/);
  assert.equal(patchIndexHtml(out, t), out, 'idempotent');
});

test('values are HTML-escaped', () => {
  const t = { ...tenant('demo-homes'), name: 'A & "B" <Homes>' };
  assert.match(patchIndexHtml(flutterIndex, t), /<title>A &amp; &quot;B&quot; &lt;Homes&gt;<\/title>/);
});

test('manifest uses the tenant name, colours and locale', () => {
  const t = tenant('realtime-estates');
  const m = JSON.parse(patchManifest('{"name":"realtor_app","icons":[1]}', t, 'Realtime Estates'));
  assert.equal(m.name, t.name);
  assert.equal(m.short_name, 'Realtime Estates');
  assert.equal(m.theme_color, t.brand.colors.primary);
  assert.equal(m.lang, 'en-KE');
  assert.deepEqual(m.icons, [1], 'keeps generated icons');
  assert.match(webDescription(t), /Live where you love/);
});
