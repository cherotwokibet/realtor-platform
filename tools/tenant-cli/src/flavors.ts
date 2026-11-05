// Android product flavors + flavor-only assets, one flavor per tenant, so
// several realtors' apps build from one checkout and install side by side.
// The app reads `appFlavor` at start-up and loads assets/flavors/<flavor>/.
// Firebase settings per flavor: `tenant firebase-config <id> <env> --flavor`. iOS schemes follow.

/** acme-realty -> acmeRealty (a valid Gradle/Xcode flavor name). */
export function flavorName(id: string): string {
  return id.replace(/-([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

export const flavorAssetDir = (flavor: string) => `assets/flavors/${flavor}`;

const BEGIN = '    # BEGIN tenant flavors (written by `tenant flavors`; keep this block empty in git)';
const END = '    # END tenant flavors';

/** Replaces the marked block under flutter.assets with one flavor-only entry per tenant. */
export function pubspecWithFlavors(pubspec: string, flavors: string[]): string {
  const start = pubspec.indexOf(BEGIN);
  const end = pubspec.indexOf(END);
  if (start < 0 || end < start) throw new Error('apps/realtor_app/pubspec.yaml has no tenant flavors block');
  const entries = flavors.flatMap((f) =>
    ['', '/fonts'].map((sub) => `    - path: ${flavorAssetDir(f)}${sub}/\n      flavors: [${f}]\n`),
  );
  return pubspec.slice(0, start + BEGIN.length) + '\n' + entries.join('') + pubspec.slice(end);
}

/** Kotlin script applied from android/app/build.gradle.kts. */
export function androidFlavorsGradle(tenants: any[]): string {
  const flavors = tenants
    .map(
      (t) => `        create("${flavorName(t.id)}") {
            dimension = "tenant"
            applicationId = "${t.apps.androidId}"
            manifestPlaceholders["appName"] = "${kotlinString(appName(t))}"
            manifestPlaceholders["shareHost"] = "${kotlinString(t.domains.share)}"
        }`,
    )
    .join('\n');
  return `// Generated from tenants/*.json by \`tenant flavors\`. Do not edit.
import com.android.build.api.dsl.ApplicationExtension

project.extensions.getByType(ApplicationExtension::class.java).apply {
    // Android Lint's release check (lintVitalAnalyzeRelease) crashes reading
    // this applied Kotlin script ("findFirCompiledSymbol only works on
    // compiled declarations"), which fails every release build. CI's
    // analyzers and tests cover the Dart code; Lint stays on for debug builds.
    lint { checkReleaseBuilds = false }
    // Release signing with the tenant's upload key (P4-s07): \`tenant release\`
    // sets these from Secret Manager; without them release builds keep the
    // template's debug key (phone tests).
    System.getenv("UPLOAD_KEYSTORE")?.let { path ->
        signingConfigs.create("upload") {
            storeFile = project.file(path)
            storePassword = System.getenv("UPLOAD_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("UPLOAD_KEY_ALIAS") ?: "upload"
            keyPassword = System.getenv("UPLOAD_KEY_PASSWORD") ?: System.getenv("UPLOAD_KEYSTORE_PASSWORD")
        }
    }
    flavorDimensions += "tenant"
    productFlavors {
${flavors}
    }
}
`;
}

/** Short launcher label: the brand name without the company suffix. */
export function appName(t: any): string {
  return String(t.name).replace(/\s+(Ltd|Limited|LLP|PLC)\.?$/i, '');
}

function kotlinString(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\$/g, '\\$');
}

const APPLY = 'apply(from = "tenant-flavors.gradle.kts")';

const DEBUG_SIGNING = 'signingConfig = signingConfigs.getByName("debug")';
const UPLOAD_OR_DEBUG = 'signingConfig = signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")';

/** Adds the apply line once, after the plugins block, and lets release
 * builds use the `upload` signing config when the flavors script made one. */
export function patchBuildGradle(src: string): string {
  let out = src.includes(DEBUG_SIGNING) && !src.includes(UPLOAD_OR_DEBUG) ? src.replace(DEBUG_SIGNING, UPLOAD_OR_DEBUG) : src;
  if (out.includes(APPLY)) return out;
  const m = /^plugins \{[\s\S]*?^\}\n/m.exec(out);
  if (!m) throw new Error('android/app/build.gradle.kts has no plugins block');
  const at = m.index + m[0].length;
  return out.slice(0, at) + '\n' + APPLY + '\n' + out.slice(at);
}

/** Share-page paths the app opens itself (App Links, P3-s07). Keep in step
 * with appLinkPaths in apps/share_pages/lib/src/app_links.dart. */
export const appLinkPaths = ['/listing/', '/area/', '/agent/'];

const APP_LINKS = `            <!-- App Links (written by \`tenant flavors\`): share-domain pages open the app. -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="https" android:host="\${shareHost}" />
${appLinkPaths.map((p) => `                <data android:pathPrefix="${p}" />`).join('\n')}
            </intent-filter>
`;

/** Each flavor's status-bar icon for push alerts (P4-s03), copied by
 * `tenant flavors` from the tenant's generated icons. */
export const NOTIFICATION_ICON = { from: 'android-notification-96.png', to: 'res/drawable-xxxhdpi/ic_notification.png' };

const PUSH_PERMISSION = `    <!-- Push alerts (written by \`tenant flavors\`): Android 13+ asks first. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
`;

const PUSH_ICON = `        <!-- Push alerts use the tenant's white glyph (written by \`tenant flavors\`). -->
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_notification" />
`;

/** The launcher label comes from each flavor's appName placeholder
 * (resValue is off by default from AGP 9), the main activity handles
 * the flavor's share-domain links, and push alerts get their permission
 * and status-bar icon. */
export function patchManifest(src: string): string {
  let out = src.replace(/android:label="[^"]*"/, 'android:label="${appName}"');
  const at = out.indexOf('</activity>');
  if (at >= 0 && !out.includes('android:host="${shareHost}"')) {
    const lineStart = out.lastIndexOf('\n', at) + 1;
    out = out.slice(0, lineStart) + APP_LINKS + out.slice(lineStart);
  }
  if (!out.includes('android.permission.POST_NOTIFICATIONS')) {
    const app = out.indexOf('    <application');
    if (app >= 0) out = out.slice(0, app) + PUSH_PERMISSION + out.slice(app);
  }
  const end = out.indexOf('    </application>');
  if (end >= 0 && !out.includes('default_notification_icon')) out = out.slice(0, end) + PUSH_ICON + out.slice(end);
  return out;
}

/** The customer app's Hosting site for a project (Terraform: google_firebase_hosting_site.app). */
export const appSiteHost = (project: string) => `${project.slice(0, 26).replace(/-$/, '')}-app.web.app`;

/**
 * The project's default Hosting domain: emailed sign-in links open through
 * it (Firebase accepts no other site as linkDomain), and Firebase Hosting
 * verifies it for the app from the SHA-256 certificates Terraform registers.
 */
export const authLinkHost = (project: string) => `${project}.firebaseapp.com`;

/** Where emailed sign-in links come back to the app (Firebase Auth's Hosting link path). */
export const EMAIL_LINK_PATH = '/__/auth/links';

/**
 * A flavor's own manifest, merged into the main one: emailed sign-in links
 * on the default Hosting domain of each of the tenant's projects open the app.
 */
export function flavorManifest(t: any): string {
  const hosts = Object.values(t.firebase.projects as Record<string, string>).map(authLinkHost);
  return `<?xml version="1.0" encoding="utf-8"?>
<!-- Generated from tenants/${t.id}.json by \`tenant flavors\`. Do not edit. -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <activity android:name=".MainActivity" android:exported="true">
            <!-- Emailed sign-in links (P4-s03): they open the app, which finishes signing in. -->
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="https" />
${hosts.map((h) => `                <data android:host="${h}" />`).join('\n')}
                <data android:pathPrefix="${EMAIL_LINK_PATH}" />
            </intent-filter>
        </activity>
    </application>
</manifest>
`;
}

/** True when [current] differs from [committed] only inside the generated flavors block. */
export function onlyFlavorBlockChanged(current: string, committed: string): boolean {
  try {
    return pubspecWithFlavors(current, []) === committed;
  } catch {
    return false;
  }
}
