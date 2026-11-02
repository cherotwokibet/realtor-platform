import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fromGoogleServices, fromServiceInfoPlist, pickApps } from '../src/firebase-config.ts';

test('picks the Android and iOS apps registered for the tenant', () => {
  const apps = [
    { platform: 'WEB' as const, appId: '1:1:web:a' },
    { platform: 'ANDROID' as const, appId: '1:1:android:other', namespace: 'com.other.app' },
    { platform: 'ANDROID' as const, appId: '1:1:android:mine', namespace: 'ke.example.app' },
    { platform: 'IOS' as const, appId: '1:1:ios:mine', namespace: 'ke.example.app' },
  ];
  assert.deepEqual(pickApps(apps, 'ke.example.app', 'ke.example.app'), { android: '1:1:android:mine', ios: '1:1:ios:mine' });
  assert.deepEqual(pickApps(apps, 'ke.none', 'ke.none'), { android: undefined, ios: undefined });
});

test('reads google-services.json for the right package', () => {
  const json = JSON.stringify({
    project_info: { project_number: '123', project_id: 'demo-project', storage_bucket: 'demo-project.appspot.com' },
    client: [
      { client_info: { mobilesdk_app_id: '1:123:android:x', android_client_info: { package_name: 'com.other' } }, api_key: [{ current_key: 'k0' }] },
      { client_info: { mobilesdk_app_id: '1:123:android:y', android_client_info: { package_name: 'ke.example.app' } }, api_key: [{ current_key: 'k1' }] },
    ],
  });
  assert.deepEqual(fromGoogleServices(json, 'ke.example.app'), {
    projectId: 'demo-project',
    messagingSenderId: '123',
    storageBucket: 'demo-project.appspot.com',
    android: { appId: '1:123:android:y', apiKey: 'k1' },
  });
  assert.throws(() => fromGoogleServices(json, 'ke.missing'), /no client/);
});

test('reads GoogleService-Info.plist', () => {
  const plist = `<plist><dict>
    <key>API_KEY</key>
    <string>ios-key</string>
    <key>GCM_SENDER_ID</key><string>123</string>
    <key>BUNDLE_ID</key><string>ke.example.app</string>
    <key>PROJECT_ID</key><string>demo-project</string>
    <key>GOOGLE_APP_ID</key><string>1:123:ios:z</string>
  </dict></plist>`;
  assert.deepEqual(fromServiceInfoPlist(plist), { appId: '1:123:ios:z', apiKey: 'ios-key', bundleId: 'ke.example.app', projectId: 'demo-project', messagingSenderId: '123' });
});
