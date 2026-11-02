import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import { listingProblems, pickBundle, playToken, publishToPlay, releaseSteps, storeListing, versionCode } from '../src/release.ts';

// Made-up tenants: nothing realtor-specific in code or tests.
const tenant = (over: object = {}) => ({
  id: 'acme-realty',
  name: 'Acme Realty Ltd',
  tagline: 'Homes you will love',
  earbNo: 'TBC',
  features: { rent: true, sale: true, shortStay: false, offPlan: true, aiSearch: false, mpesa: false },
  ...over,
});

test('the listing is made from the tenant file, within Play limits', () => {
  const l = storeListing(tenant());
  assert.equal(l.title, 'Acme Realty');
  assert.equal(l.shortDescription, 'Homes to rent or buy from Acme Realty. Homes you will love');
  assert.match(l.fullDescription, /Off-plan projects/);
  assert.doesNotMatch(l.fullDescription, /EARB/, 'no registration line while it is TBC');
  assert.doesNotMatch(l.fullDescription, /M-Pesa|Just type/, 'only switched-on features');
  assert.deepEqual(listingProblems(l), []);
  assert.match(storeListing(tenant({ earbNo: 'BRN/123' })).fullDescription, /EARB BRN\/123/);
});

test('store.listing in the tenant file wins, and over-long text is refused', () => {
  const l = storeListing(tenant({ store: { listing: { title: 'Acme Homes', shortDescription: 'Find a home in Nairobi.' } } }));
  assert.equal(l.title, 'Acme Homes');
  assert.equal(l.shortDescription, 'Find a home in Nairobi.');
  assert.deepEqual(listingProblems({ ...l, title: 'x'.repeat(31) }), ['title is 31 characters; Play allows 30']);
});

test('version codes always go up and fit Play', () => {
  const a = versionCode(new Date('2026-11-02T14:00:00Z'));
  assert.ok(versionCode(new Date('2026-11-02T14:01:00Z')) > a);
  assert.ok(a < 2_100_000_000);
});

test('the build makes every flavor but bundles only this one', () => {
  const steps = releaseSteps('acme-realty', ['acmeRealty', 'otherHomes'], 123);
  const build = steps.at(-1)!.argv;
  assert.deepEqual(build, ['flutter', 'build', 'appbundle', '--release', '--flavor', 'acmeRealty', '--build-number', '123']);
  assert.ok(steps.some((s) => s.argv.join(' ') === 'node ../../tools/tenant-cli/src/cli.ts firebase-config acme-realty prod --flavor'));
  assert.ok(steps.some((s) => s.argv.includes('acmeRealty,otherHomes')));
});

test('the bundle is found whatever case Gradle gave the flavor', () => {
  const paths = ['otherHomesRelease/app-otherHomes-release.aab', 'acmerealtyRelease/app-acmerealty-release.aab'];
  assert.equal(pickBundle(paths, 'acme-realty'), 'acmerealtyRelease/app-acmerealty-release.aab');
  assert.equal(pickBundle(['acmeRealtyDebug/app-acmeRealty-debug.aab'], 'acme-realty'), undefined);
});

test('the service-account token request is a JWT signed with its key', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  let body = '';
  const token = await playToken(
    { client_email: 'release@acme.iam.gserviceaccount.com', private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }).toString() },
    new Date('2026-11-02T14:00:00Z'),
    (async (_url: string, init: RequestInit) => {
      body = String(init.body);
      return new Response(JSON.stringify({ access_token: 'tok' }));
    }) as typeof fetch,
  );
  assert.equal(token, 'tok');
  const jwt = new URLSearchParams(body).get('assertion')!;
  const [h, c, s] = jwt.split('.');
  assert.ok(createVerify('RSA-SHA256').update(`${h}.${c}`).verify(publicKey, s, 'base64url'));
  const claims = JSON.parse(Buffer.from(c, 'base64url').toString());
  assert.equal(claims.scope, 'https://www.googleapis.com/auth/androidpublisher');
  assert.equal(claims.exp - claims.iat, 3600);
});

function fakePlay(failAt?: string) {
  const calls: string[] = [];
  const fn = (async (url: string, init: RequestInit) => {
    const path = url.replace(/^https:\/\/androidpublisher\.googleapis\.com/, '');
    calls.push(`${init.method} ${path}`);
    if (failAt && path.includes(failAt)) return new Response('nope', { status: 403 });
    if (path.endsWith('/edits')) return new Response(JSON.stringify({ id: 'e1' }));
    if (path.includes('/bundles')) return new Response(JSON.stringify({ versionCode: 42 }));
    return new Response(JSON.stringify({}));
  }) as typeof fetch;
  return { calls, fn };
}

const upload = { packageName: 'com.acme.app', bundle: new Uint8Array([1, 2, 3]), track: 'internal' as const, listing: storeListing(tenant()), language: 'en-GB', notes: 'Build abc', status: 'completed' as const };

test('a release is one Play edit: bundle, track, listing, commit', async () => {
  const play = fakePlay();
  assert.equal(await publishToPlay('tok', upload, play.fn), 42);
  assert.deepEqual(play.calls, [
    'POST /androidpublisher/v3/applications/com.acme.app/edits',
    'POST /upload/androidpublisher/v3/applications/com.acme.app/edits/e1/bundles?uploadType=media',
    'PUT /androidpublisher/v3/applications/com.acme.app/edits/e1/tracks/internal',
    'PUT /androidpublisher/v3/applications/com.acme.app/edits/e1/listings/en-GB',
    'POST /androidpublisher/v3/applications/com.acme.app/edits/e1:commit',
  ]);
});

test('closed testing is Play\'s alpha track; a failure never commits', async () => {
  const play = fakePlay('/listings/');
  await assert.rejects(publishToPlay('tok', { ...upload, track: 'closed' }, play.fn), /update the listing text failed \(403\)/);
  assert.ok(play.calls.some((c) => c.endsWith('/tracks/alpha')));
  assert.ok(!play.calls.some((c) => c.endsWith(':commit')));
});
