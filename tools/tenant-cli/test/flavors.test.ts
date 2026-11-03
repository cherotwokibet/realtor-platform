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
  appLinkPaths,
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
  // Lint's release check crashes on this script; release builds must still work.
  assert.match(g, /lint \{ checkReleaseBuilds = false \}/);
  // Release signing with the upload key only when `tenant release` provides it.
  assert.match(g, /System\.getenv\("UPLOAD_KEYSTORE"\)\?\.let \{ path ->\n\s+signingConfigs\.create\("upload"\)/);
});

test('release builds sign with the upload key when there is one, else the debug key', () => {
  const template = 'plugins {\n}\n\nandroid {\n    buildTypes {\n        release {\n            signingConfig = signingConfigs.getByName("debug")\n        }\n    }\n}\n';
  const once = patchBuildGradle(template);
  assert.match(once, /signingConfig = signingConfigs\.findByName\("upload"\) \?: signingConfigs\.getByName\("debug"\)/);
  assert.equal(patchBuildGradle(once), once);
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

// What `flutter create --platforms=android` writes (trimmed).
const flutterManifest = `<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="realtor_app"
        android:name="\${applicationName}">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>`;

test('the main activity opens share-domain links (App Links), once', () => {
  const once = patchManifest(flutterManifest);
  assert.match(once, /<intent-filter android:autoVerify="true">[\s\S]*android:host="\$\{shareHost\}"[\s\S]*<\/intent-filter>\n        <\/activity>/);
  for (const p of ['/listing/', '/area/', '/agent/']) assert.ok(once.includes(`android:pathPrefix="${p}"`), p);
  assert.match(once, /android.intent.action.MAIN/, 'launcher filter kept');
  assert.equal(patchManifest(once), once);
});

test('push alerts: the notification permission and the status-bar icon, once', () => {
  const once = patchManifest(flutterManifest);
  assert.match(once, /<uses-permission android:name="android.permission.POST_NOTIFICATIONS" \/>\n    <application/);
  assert.match(once, /default_notification_icon"\n\s+android:resource="@drawable\/ic_notification" \/>\n    <\/application>/);
  assert.equal(patchManifest(once), once);
});

test('each flavor sets its own share host', () => {
  const g = androidFlavorsGradle([tenant('realtime-estates'), tenant('demo-homes')]);
  assert.match(g, /create\("realtimeEstates"\)[\s\S]*?manifestPlaceholders\["shareHost"\] = "realtimeestates\.co\.ke"/);
  assert.match(g, /create\("demoHomes"\)[\s\S]*?manifestPlaceholders\["shareHost"\] = "demohomes\.example\.com"/);
});

test('app-link paths match the share server\'s', () => {
  const dart = readFileSync(join(repoRoot(), 'apps/share_pages/lib/src/app_links.dart'), 'utf8');
  const list = /const appLinkPaths = \[([^\]]*)\]/.exec(dart)![1];
  assert.deepEqual([...list.matchAll(/'([^']+)'/g)].map((m) => m[1]), appLinkPaths);
});
