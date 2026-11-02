/**
 * `tenant release <id> [--track=internal|closed]` (P4-s07): builds the
 * tenant's Android App Bundle signed with its upload key and sends it, with
 * the store listing text, to a Google Play testing track. Production is
 * promoted by a person in the Play Console, never from here.
 *
 * No secret is in the repo, printed, or passed on a command line: the
 * service account, upload keystore and its password are read from Secret
 * Manager in the tenant's prod project (names below), written to a 0600
 * temp folder for the build, and deleted after. This file plans and talks
 * to the Play Developer API; cli.ts runs the steps.
 */
import { createSign } from 'node:crypto';
import { appName, flavorName } from './flavors.ts';

/** Secret Manager names in the tenant's prod project (`secret://<name>`). */
export const RELEASE_SECRETS = {
  /** The Play Console service account's JSON key (Release manager on this app only). */
  serviceAccount: 'play-service-account',
  /** The upload keystore (.jks), base64. Play App Signing holds the app signing key. */
  keystore: 'android-upload-keystore',
  keystorePassword: 'android-upload-keystore-password',
} as const;

export const KEY_ALIAS = 'upload';

/** Our names -> Play track ids. Production is promoted in the Play Console. */
export const TRACKS = { internal: 'internal', closed: 'alpha' } as const;
export type Track = keyof typeof TRACKS;

export interface Listing {
  title: string;
  shortDescription: string;
  fullDescription: string;
}

const LIMITS = { title: 30, shortDescription: 80, fullDescription: 4000 } as const;

/**
 * The Play listing: the tenant file's `store.listing` where given, else
 * made from its name, tagline and switched-on features.
 */
export function storeListing(t: any): Listing {
  const own = t.store?.listing ?? {};
  const f = t.features ?? {};
  const what = [f.rent && 'rent', f.sale && 'buy', f.shortStay && 'book a short stay'].filter(Boolean) as string[];
  const doing = what.length > 1 ? `${what.slice(0, -1).join(', ')} or ${what.at(-1)}` : (what[0] ?? 'find');
  const bullets = [
    'Search by area, budget, bedrooms and type, and save the homes you like on your phone.',
    'Verified listings show when an agent last confirmed the home is still available.',
    'Ask about a home or book a viewing in a few taps, or chat on WhatsApp.',
    'Get alerts when new homes match a search you saved.',
    f.offPlan && 'Off-plan projects: units, prices from, payment plans and handover dates.',
    f.aiSearch && 'Just type what you want, e.g. "2 bedroom Kilimani under 60k with parking".',
    f.mpesa && 'Pay viewing fees and deposits with M-Pesa.',
  ].filter(Boolean) as string[];
  return {
    title: own.title ?? appName(t),
    shortDescription: own.shortDescription ?? `Homes to ${doing} from ${appName(t)}. ${t.tagline ?? ''}`.trim(),
    fullDescription:
      own.fullDescription ??
      [
        `${t.name}: ${t.tagline ?? 'homes in Kenya'}.`,
        `Find a home to ${doing} with ${appName(t)}.`,
        bullets.map((b) => `• ${b}`).join('\n'),
        t.earbNo && t.earbNo !== 'TBC' ? `${t.name} is registered with the Estate Agents Registration Board (EARB ${t.earbNo}).` : '',
      ]
        .filter(Boolean)
        .join('\n\n'),
  };
}

/** What Play would refuse in the listing text. */
export function listingProblems(l: Listing): string[] {
  return (Object.keys(LIMITS) as (keyof Listing)[]).flatMap((k) =>
    !l[k].trim() ? [`${k} is empty`] : l[k].length > LIMITS[k] ? [`${k} is ${l[k].length} characters; Play allows ${LIMITS[k]}`] : [],
  );
}

/** Minutes since 1970: always higher than the last upload, under Play's 2,100,000,000. */
export const versionCode = (now: Date) => Math.floor(now.getTime() / 60_000);

export interface BuildStep {
  title: string;
  argv: string[];
  /** Repo-relative. */
  cwd: string;
  skipIfExists?: string;
}

const APP = 'apps/realtor_app';

/** The App Bundle build for one tenant, every flavor generated (as in CI). */
export function releaseSteps(id: string, allFlavors: string[], buildNumber: number): BuildStep[] {
  const cli = '../../tools/tenant-cli/src/cli.ts';
  return [
    { title: 'Android folder', argv: ['flutter', 'create', '.', '--platforms=android', '--project-name', 'realtor_app'], cwd: APP, skipIfExists: `${APP}/android` },
    { title: 'Flavors', argv: ['node', cli, 'flavors'], cwd: APP },
    { title: 'Firebase settings (prod)', argv: ['node', cli, 'firebase-config', id, 'prod', '--flavor'], cwd: APP },
    { title: 'Packages', argv: ['flutter', 'pub', 'get'], cwd: APP },
    { title: 'Launcher icons', argv: ['dart', 'run', 'flutter_launcher_icons'], cwd: APP },
    { title: 'Splash screens', argv: ['dart', 'run', 'flutter_native_splash:create', '--flavors', allFlavors.join(',')], cwd: APP },
    {
      title: 'App Bundle (signed with the upload key)',
      argv: ['flutter', 'build', 'appbundle', '--release', '--flavor', flavorName(id), '--build-number', String(buildNumber)],
      cwd: APP,
    },
  ];
}

/** Where `flutter build appbundle --flavor <f>` writes bundles. */
export const BUNDLE_DIR = `${APP}/build/app/outputs/bundle`;

/** The tenant's release bundle among the paths under BUNDLE_DIR (Gradle may
 * lower-case the flavor, e.g. realtimeestatesRelease/app-realtimeestates-release.aab). */
export function pickBundle(paths: string[], id: string): string | undefined {
  const want = `${flavorName(id)}-release.aab`.toLowerCase();
  return paths.find((p) => p.toLowerCase().endsWith(want));
}

/** Env for the build: Gradle's `upload` signing config reads these (flavors.ts). */
export const signingEnv = (keystorePath: string, password: string) => ({
  UPLOAD_KEYSTORE: keystorePath,
  UPLOAD_KEYSTORE_PASSWORD: password,
  UPLOAD_KEY_ALIAS: KEY_ALIAS,
});

// ---- Google Play Developer API (androidpublisher v3), no SDK ----

type Fetch = typeof fetch;
const API = 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications';
const UPLOAD = 'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications';

/** A signed JWT for the service account, exchanged for an access token. */
export async function playToken(serviceAccount: { client_email: string; private_key: string }, now: Date, fetchFn: Fetch = fetch): Promise<string> {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const iat = Math.floor(now.getTime() / 1000);
  const unsigned = `${b64({ alg: 'RS256', typ: 'JWT' })}.${b64({
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/androidpublisher',
    aud: 'https://oauth2.googleapis.com/token',
    iat,
    exp: iat + 3600,
  })}`;
  const sig = createSign('RSA-SHA256').update(unsigned).sign(serviceAccount.private_key, 'base64url');
  const res = await fetchFn('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${sig}` }),
  });
  if (!res.ok) throw new Error(`Google sign-in for the service account failed (${res.status})`);
  return ((await res.json()) as { access_token: string }).access_token;
}

export interface Upload {
  packageName: string;
  bundle: Uint8Array;
  track: Track;
  listing: Listing;
  /** Play's language code for the listing (the tenant's `store.language`, else en-GB). */
  language: string;
  /** Release notes shown to testers. */
  notes: string;
  /** `draft` until the app has had its first release reviewed in the Console. */
  status: 'completed' | 'draft';
}

/**
 * One Play "edit": upload the bundle, put it on the track, update the
 * listing text, commit. Nothing is live until the commit, and a failure
 * before it leaves the Console as it was. Completes with the version code.
 */
export async function publishToPlay(token: string, u: Upload, fetchFn: Fetch = fetch): Promise<number> {
  const auth = { authorization: `Bearer ${token}` };
  const app = `${API}/${encodeURIComponent(u.packageName)}`;
  const call = async (what: string, url: string, init: RequestInit) => {
    const res = await fetchFn(url, { ...init, headers: { ...auth, ...(init.headers as object) } });
    if (!res.ok) throw new Error(`Play: ${what} failed (${res.status}): ${(await res.text()).slice(0, 300)}`);
    return res.json() as Promise<any>;
  };
  const json = (body: object): RequestInit => ({ body: JSON.stringify(body), headers: { 'content-type': 'application/json' } });
  const edit = await call('start an edit', `${app}/edits`, { method: 'POST', ...json({}) });
  const e = `${app}/edits/${edit.id}`;
  const bundle = await call('upload the bundle', `${UPLOAD}/${encodeURIComponent(u.packageName)}/edits/${edit.id}/bundles?uploadType=media`, {
    method: 'POST',
    body: new Blob([u.bundle as Uint8Array<ArrayBuffer>]),
    headers: { 'content-type': 'application/octet-stream' },
  });
  const code = Number(bundle.versionCode);
  const track = TRACKS[u.track];
  await call(`put it on the ${u.track} track`, `${e}/tracks/${track}`, {
    method: 'PUT',
    ...json({ track, releases: [{ versionCodes: [String(code)], status: u.status, releaseNotes: [{ language: u.language, text: u.notes.slice(0, 500) }] }] }),
  });
  await call('update the listing text', `${e}/listings/${u.language}`, { method: 'PUT', ...json({ language: u.language, ...u.listing }) });
  await call('commit', `${e}:commit`, { method: 'POST' });
  return code;
}
