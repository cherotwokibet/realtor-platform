import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  flavorName,
  appName,
  pubspecWithFlavors,
  androidFlavorsGradle,
  patchBuildGradle,
  patchManifest,
} from '../src/flavors.ts';
import { repoRoot } from '../src/validate.ts';

const tenant = (id: string) => JSON.parse(readFileSync(join(repoRoot(), 'tenants', `${id}.json`), 'utf8'));

test('flavor names are valid identifiers', () => {
  assert.equal(flavorName('realtime-estates'), 'realtimeEstates');
  assert.equal(flavorName('demo-homes'), 'demoHomes');
  assert.equal(flavorName('acme'), 'acme');
});

test('launcher label drops the company suffix', () => {
  assert.equal(appName(tenant('realtime-estates')), 'Realtime Estates');
  assert.equal(appName(tenant('demo-homes')), 'Demo Homes');
});

test('pubspec block lists flavor-only assets and is idempotent', () => {
  const src = readFileSync(join(repoRoot(), 'apps/realtor_app/pubspec.yaml'), 'utf8');
  const once = pubspecWithFlavors(src, ['realtimeEstates', 'demoHomes']);
  assert.match(once, /- path: assets\/flavors\/demoHomes\/fonts\/\n {6}flavors: \[demoHomes\]/);
  assert.equal(pubspecWithFlavors(once, ['realtimeEstates', 'demoHomes']), once);
  assert.equal(pubspecWithFlavors(once, []), src, 'clearing restores the committed file');
});

test('each tenant gets its own application id', () => {
  const g = androidFlavorsGradle([tenant('realtime-estates'), tenant('demo-homes')]);
  assert.match(g, /create\("realtimeEstates"\) \{\n\s+dimension = "tenant"\n\s+applicationId = "ke\.co\.realtimeestates\.app"/);
  assert.match(g, /create\("demoHomes"\)[\s\S]*applicationId = "com\.example\.demohomes"/);
  assert.match(g, /manifestPlaceholders\["appName"\] = "Realtime Estates"/);
});

test('gradle and manifest patches apply once', () => {
  const gradle = 'plugins {\n    id("com.android.application")\n}\n\nandroid {\n}\n';
  const once = patchBuildGradle(gradle);
  assert.match(once, /^plugins \{[\s\S]*?\}\n\napply\(from = "tenant-flavors\.gradle\.kts"\)\n\nandroid/);
  assert.equal(patchBuildGradle(once), once);
  assert.equal(
    patchManifest('<application\n        android:label="realtor_app"\n        android:name="${applicationName}"'),
    '<application\n        android:label="${appName}"\n        android:name="${applicationName}"',
  );
});
