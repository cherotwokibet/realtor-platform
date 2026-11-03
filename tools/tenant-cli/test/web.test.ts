import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ADMIN_ROBOTS, APP_ROBOTS, patchAdminIndexHtml, patchIndexHtml, patchManifest, webDescription } from '../src/web.ts';
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

test('old #/ links are rewritten to paths before Flutter starts, once', () => {
  const once = patchIndexHtml(flutterIndex, tenant('demo-homes'));
  const script = /<script>([^<]*)<\/script>\n<\/head>/.exec(once);
  assert.ok(script, 'redirect script sits in <head>');
  const calls: string[] = [];
  const location = { hash: '#/listing/2-bedroom-apartment-kilimani' };
  const history = { replaceState: (_s: unknown, _t: string, url: string) => calls.push(url) };
  new Function('location', 'history', script[1])(location, history);
  assert.deepEqual(calls, ['/listing/2-bedroom-apartment-kilimani']);
  new Function('location', 'history', script[1])({ hash: '#enquire' }, history);
  assert.equal(calls.length, 1, 'plain anchors are left alone');
  assert.equal(patchIndexHtml(once, tenant('demo-homes')), once);
});

test('a loading screen paints the tenant name at once, and goes on Flutter\'s first frame (P3-s01)', () => {
  const t = tenant('realtime-estates');
  const out = patchIndexHtml(flutterIndex, t);
  assert.match(out, /<div id="loading" aria-hidden="true">Realtime Estates Ltd<small>Live where you love<\/small><\/div>/);
  assert.match(out, new RegExp(`#loading\\{[^}]*background:${t.brand.colors.background};color:${t.brand.colors.primary}`));
  assert.match(out, /flutter-first-frame/);
  assert.equal(patchIndexHtml(out, t), out, 'still idempotent');
});

test('the admin shell: tenant title, kept out of search, robots.txt disallows all', () => {
  const t = tenant('demo-homes');
  const out = patchAdminIndexHtml(flutterIndex.replace('realtor_app', 'realtor_admin').replace('realtor_app', 'realtor_admin'), t);
  assert.match(out, /<title>Demo Homes admin<\/title>/);
  assert.match(out, /<meta name="robots" content="noindex, nofollow">/);
  assert.doesNotMatch(out, /A new Flutter project|realtor_admin/);
  assert.match(out, /<div id="loading" aria-hidden="true">Demo Homes<small>Admin<\/small><\/div>/);
  assert.equal(ADMIN_ROBOTS, 'User-agent: *\nDisallow: /\n');
});

test('the customer app gets a valid robots.txt that lets crawlers in', () => {
  assert.equal(APP_ROBOTS, 'User-agent: *\nAllow: /\n');
});
