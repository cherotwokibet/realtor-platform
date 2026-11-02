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

/** Adds the apply line once, after the plugins block. */
export function patchBuildGradle(src: string): string {
  if (src.includes(APPLY)) return src;
  const m = /^plugins \{[\s\S]*?^\}\n/m.exec(src);
  if (!m) throw new Error('android/app/build.gradle.kts has no plugins block');
  const at = m.index + m[0].length;
  return src.slice(0, at) + '\n' + APPLY + '\n' + src.slice(at);
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

/** The launcher label comes from each flavor's appName placeholder
 * (resValue is off by default from AGP 9), and the main activity handles
 * the flavor's share-domain links. */
export function patchManifest(src: string): string {
  let out = src.replace(/android:label="[^"]*"/, 'android:label="${appName}"');
  const at = out.indexOf('</activity>');
  if (at >= 0 && !out.includes('android:host="${shareHost}"')) {
    const lineStart = out.lastIndexOf('\n', at) + 1;
    out = out.slice(0, lineStart) + APP_LINKS + out.slice(lineStart);
  }
  return out;
}
