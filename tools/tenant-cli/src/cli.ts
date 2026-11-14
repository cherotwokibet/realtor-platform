#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, copyFileSync, rmSync, readdirSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { execSync, spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline/promises';
import { join, basename, relative } from 'node:path';
import { validateTenants, repoRoot } from './validate.ts';
import { tenantCss } from './css.ts';
import { generateIcons, writeHomeImages } from './icons.ts';
import { flutterConfigs } from './flutter-config.ts';
import { createTenant } from './create.ts';
import { rebrandTenant } from './rebrand.ts';
import { ADMIN_ROBOTS, APP_ROBOTS, appAssetLinks, patchAdminIndexHtml, patchIndexHtml, patchManifest as patchWebManifest } from './web.ts';
import { tenantFontFiles } from './fonts.ts';
import { ENVS, type Env, blockingChanges, deploySteps, failedFunctions, functionBatches, imageRepo, parseBilling, parseParts, planProblems, planSummary, shellLine } from './deploy.ts';
import { RELEASE_SECRETS, TRACKS, type Track, BUNDLE_DIR, pickBundle, listingProblems, publishToPlay, playToken, releaseSteps, signingEnv, storeListing, versionCode } from './release.ts';
import { fromGoogleServices, fromServiceInfoPlist, type MobileFirebase, pickApps } from './firebase-config.ts';
import {
  flavorName,
  appName,
  flavorAssetDir,
  NOTIFICATION_ICON,
  flavorManifest,
  onlyFlavorBlockChanged,
  pubspecWithFlavors,
  androidFlavorsGradle,
  patchBuildGradle,
  patchManifest,
} from './flavors.ts';

const [cmd, ...args] = process.argv.slice(2);

function usage(): never {
  console.log(`tenant <command>

  validate [id...]   Check tenant files against the schema, assets and colour contrast
  css <id>           Write build/tokens/<id>.css for the share pages
  icons <id>         Generate app icons, splash, favicons, PWA and share images into brand/<id>/generated
  prepare <id>       Generate icons, then copy the tenant file, logos and fonts into assets/tenant of the app and the admin
  flavors [id...]    One Android flavor per tenant (default: all): assets/flavors/<flavor>/, flavor-only
                     pubspec assets, per-flavor icon + splash configs, productFlavors in android/app

  web <id>           Rewrite apps/realtor_app/web/index.html and manifest.json for the tenant
                     (title, description, theme colour, Open Graph); run after flutter create
  create <id> <name>  Scaffold tenants/<id>.json and placeholder brand/<id>/ art for a new realtor
                     (provisioning: infra/terraform/README.md)
  rebrand <id> <name> --from <demo-id> --primary <hex> [--accent <hex>]
                     Sales demo (P8-s05): the demo tenant under a prospect's name and colours,
                     with a readable palette and placeholder art; see docs/sales-demo.md
  firebase-config <id> <dev|stage|prod> [--flavor]
                     After prepare (or flavors): fetch the Android/iOS Firebase settings with the
                     firebase CLI into the app's firebase.json asset (generated, not committed)
  deploy <id> <dev|stage|prod> [--only=functions,images,infra,web] [--dry-run] [--yes]
                     In Cloud Shell: Functions, both images (tagged with the commit), Terraform
                     (refuses a plan that would change billing, delete anything or point Cloud Run
                     outside the project's repo; asks before applying) and the Hosting sites

  release <id> [--track=internal|closed] [--status=completed|draft] [--notes="…"] [--dry-run]
                     In Cloud Shell: the tenant's Android App Bundle, signed with its upload key from
                     Secret Manager (prod project), with the store listing, to a Google Play testing
                     track; production is promoted in the Play Console. See docs/store-release.md

Coming later: iOS flavors and TestFlight`);
  process.exit(cmd ? 1 : 0);
}

function loadValid(id: string): any {
  const bad = validateTenants(repoRoot(), [id]).find((r) => r.errors.length);
  if (bad) {
    console.error(`✗ ${bad.file} is invalid; run "tenant validate ${id}"`);
    for (const e of bad.errors) console.error(`    ${e}`);
    process.exit(1);
  }
  return JSON.parse(readFileSync(join(repoRoot(), 'tenants', `${id}.json`), 'utf8'));
}

/**
 * Uncommitted changes that would make a build differ from its commit. The
 * flavors block `tenant flavors` writes into the app's pubspec.yaml doesn't
 * count: it is generated, and phone builds leave it behind.
 */
function uncommitted(root: string): string[] {
  const pubspec = 'apps/realtor_app/pubspec.yaml';
  return blockingChanges(execSync('git status --porcelain', { cwd: root, encoding: 'utf8' })).filter((path) => {
    if (path !== pubspec) return true;
    const committed = execSync(`git show HEAD:${pubspec}`, { cwd: root, encoding: 'utf8' });
    return !onlyFlavorBlockChanged(readFileSync(join(root, pubspec), 'utf8'), committed);
  });
}

function resetDir(dir: string): void {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, '.gitkeep'), '');
}

/**
 * Tenant file, logos, fonts (+ manifest) and icon inputs, under apps/realtor_app/<rel>.
 * Apps in [alsoTo] (the admin) get the same files except the icon inputs.
 */
async function writeAppAssets(root: string, t: any, rel: string, alsoTo: string[] = []): Promise<void> {
  const r = await generateIcons(root, t);
  const fonts = tenantFontFiles(t);
  for (const app of ['realtor_app', ...alsoTo]) {
    const out = join(root, 'apps', app, rel);
    resetDir(out);
    writeFileSync(join(out, 'tenant.json'), JSON.stringify(t, null, 2));
    // Fixed file names: the app refers to these, never to a realtor's own names.
    for (const f of ['logo-horizontal.png', 'logo-horizontal-reverse.png', 'logo-stacked.png', 'mark.png']) {
      copyFileSync(join(r.outDir, f), join(out, f));
    }
    // Fonts: the app registers every entry of fonts.json before the first frame.
    mkdirSync(join(out, 'fonts'), { recursive: true });
    for (const f of fonts) copyFileSync(join(root, f.source), join(out, 'fonts', f.file));
    writeFileSync(
      join(out, 'fonts.json'),
      JSON.stringify(fonts.map((f) => ({ family: f.family, weight: f.weight, asset: `${rel}/fonts/${f.file}` })), null, 2),
    );
    if (app !== 'realtor_app') continue;
    // Home page photos, when the tenant has some.
    await writeHomeImages(root, t, out);
    // Launcher icon + splash inputs live in a subfolder, which Flutter does not bundle.
    mkdirSync(join(out, 'icons'), { recursive: true });
    for (const f of r.files.filter((f) => f.endsWith('.png'))) copyFileSync(join(r.outDir, f), join(out, 'icons', f));
  }
}

/** Runs a command with its output shown as it comes and returned when it ends. */
function runTee(argv: string[], cwd: string, env?: Record<string, string>): Promise<{ status: number; output: string }> {
  return new Promise((resolve) => {
    const child = spawn(argv[0], argv.slice(1), { cwd, env: { ...process.env, ...env }, stdio: ['inherit', 'pipe', 'pipe'] });
    let output = '';
    child.stdout.on('data', (d) => {
      process.stdout.write(d);
      output += d;
    });
    child.stderr.on('data', (d) => {
      process.stderr.write(d);
      output += d;
    });
    child.on('close', (code) => resolve({ status: code ?? 1, output }));
  });
}

switch (cmd) {
  case 'validate': {
    const results = validateTenants(repoRoot(), args);
    let failed = 0;
    for (const r of results) {
      if (r.errors.length) {
        failed++;
        console.error(`✗ ${r.file}`);
        for (const e of r.errors) console.error(`    ${e}`);
      } else console.log(`✓ ${r.file}`);
    }
    if (!results.length) console.error('No tenant files found.');
    process.exit(failed || !results.length ? 1 : 0);
  }
  case 'css': {
    const id = args[0];
    if (!id) usage();
    const t = JSON.parse(readFileSync(join(repoRoot(), 'tenants', `${id}.json`), 'utf8'));
    const out = join(repoRoot(), 'build', 'tokens');
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, `${id}.css`), tenantCss(t));
    console.log(`wrote build/tokens/${id}.css`);
    break;
  }
  case 'create': {
    const [id, ...nameParts] = args;
    if (!id || !nameParts.length) usage();
    try {
      createTenant(repoRoot(), id, nameParts.join(' '));
    } catch (e) {
      console.error(`✗ ${(e as Error).message}`);
      process.exit(1);
    }
    loadValid(id);
    console.log(`created tenants/${id}.json and brand/${id}/ (placeholder art)
next:
  1. replace TBC / example.com values, colours, fonts and the SVGs in brand/${id}/
  2. node tools/tenant-cli/src/cli.ts validate ${id}
  3. provision (Boniface, with billing): see infra/terraform/README.md`);
    break;
  }
  case 'rebrand': {
    const flag = (n: string) => {
      const i = args.indexOf(`--${n}`);
      return i >= 0 ? args.splice(i, 2)[1] : undefined;
    };
    const primary = flag('primary');
    const accent = flag('accent');
    const from = flag('from');
    const [id, ...nameParts] = args;
    if (!id || !nameParts.length || !primary || !from) usage();
    try {
      const { notes } = rebrandTenant(repoRoot(), id, nameParts.join(' '), { primary, accent, from });
      loadValid(id);
      for (const n of notes) console.log(`  adjusted: ${n}`);
    } catch (e) {
      console.error(`✗ ${(e as Error).message}`);
      process.exit(1);
    }
    console.log(`demo tenant ${id} ready (do not commit tenants/${id}.json or brand/${id}/)
next:
  node tools/tenant-cli/src/cli.ts prepare ${id}
  cd apps/realtor_app && flutter run -d chrome     (and apps/admin for the staff side)`);
    break;
  }
  case 'web': {
    const id = args[0];
    if (!id) usage();
    const t = loadValid(id);
    const root = repoRoot();
    const web = join(root, 'apps', 'realtor_app', 'web');
    if (!existsSync(join(web, 'index.html'))) {
      console.error('✗ no apps/realtor_app/web: run `flutter create . --platforms=web` first');
      process.exit(1);
    }
    // The fonts `tenant prepare` bundled, preloaded with the engine.
    const fontsJson = join(root, 'apps', 'realtor_app', 'assets', 'tenant', 'fonts.json');
    const fonts = existsSync(fontsJson) ? (JSON.parse(readFileSync(fontsJson, 'utf8')) as { asset: string }[]).map((f) => f.asset) : [];
    writeFileSync(join(web, 'index.html'), patchIndexHtml(readFileSync(join(web, 'index.html'), 'utf8'), t, fonts));
    writeFileSync(join(web, 'robots.txt'), APP_ROBOTS);
    // Android opens emailed sign-in links in the app (firebase.json keeps .well-known).
    mkdirSync(join(web, '.well-known'), { recursive: true });
    writeFileSync(join(web, '.well-known', 'assetlinks.json'), appAssetLinks(t));
    // The admin's shell too, when it exists: title, noindex, robots.txt, loading screen.
    const adminWeb = join(root, 'apps', 'admin', 'web');
    if (existsSync(join(adminWeb, 'index.html'))) {
      writeFileSync(join(adminWeb, 'index.html'), patchAdminIndexHtml(readFileSync(join(adminWeb, 'index.html'), 'utf8'), t));
      writeFileSync(join(adminWeb, 'robots.txt'), ADMIN_ROBOTS);
    }
    writeFileSync(join(web, 'manifest.json'), patchWebManifest(readFileSync(join(web, 'manifest.json'), 'utf8'), t, appName(t)));
    const og = join(root, 'brand', id, 'generated', 'og-default-1200x630.png');
    if (existsSync(og)) copyFileSync(og, join(web, 'og.png'));
    console.log(`web shell → ${t.name}`);
    break;
  }
  case 'icons': {
    const id = args[0];
    if (!id) usage();
    const t = loadValid(id);
    const r = await generateIcons(repoRoot(), t);
    console.log(`generated ${r.files.length} files → brand/${id}/generated`);
    break;
  }
  case 'prepare': {
    const id = args[0];
    if (!id) usage();
    const root = repoRoot();
    const t = loadValid(id);
    await writeAppAssets(root, t, 'assets/tenant', ['admin']);
    const app = join(root, 'apps', 'realtor_app');
    const cfg = flutterConfigs(t);
    writeFileSync(join(app, 'flutter_launcher_icons.yaml'), cfg.launcherIcons);
    writeFileSync(join(app, 'flutter_native_splash.yaml'), cfg.nativeSplash);
    console.log(`prepared ${id} → apps/realtor_app and apps/admin assets/tenant (icons in brand/${id}/generated)`);
    break;
  }
  case 'flavors': {
    const root = repoRoot();
    const ids = args.length ? args : readdirSync(join(root, 'tenants')).filter((f) => f.endsWith('.json')).map((f) => basename(f, '.json'));
    const tenants = ids.map(loadValid);
    const app = join(root, 'apps', 'realtor_app');
    // Single-tenant assets would be bundled into every flavor: empty them.
    resetDir(join(app, 'assets', 'tenant'));
    mkdirSync(join(app, 'assets', 'tenant', 'fonts'));
    rmSync(join(app, 'assets', 'flavors'), { recursive: true, force: true });
    for (const t of tenants) {
      const f = flavorName(t.id);
      await writeAppAssets(root, t, flavorAssetDir(f));
      const cfg = flutterConfigs(t, `${flavorAssetDir(f)}/icons`, true);
      writeFileSync(join(app, `flutter_launcher_icons-${f}.yaml`), cfg.launcherIcons);
      writeFileSync(join(app, `flutter_native_splash-${f}.yaml`), cfg.nativeSplash);
    }
    const flavors = tenants.map((t) => flavorName(t.id));
    const pubspec = join(app, 'pubspec.yaml');
    writeFileSync(pubspec, pubspecWithFlavors(readFileSync(pubspec, 'utf8'), flavors));
    const gradle = join(app, 'android', 'app', 'build.gradle.kts');
    if (existsSync(gradle)) {
      writeFileSync(join(app, 'android', 'app', 'tenant-flavors.gradle.kts'), androidFlavorsGradle(tenants));
      writeFileSync(gradle, patchBuildGradle(readFileSync(gradle, 'utf8')));
      const manifest = join(app, 'android', 'app', 'src', 'main', 'AndroidManifest.xml');
      writeFileSync(manifest, patchManifest(readFileSync(manifest, 'utf8')));
      for (const t of tenants) {
        mkdirSync(join(app, 'android', 'app', 'src', flavorName(t.id)), { recursive: true });
        writeFileSync(join(app, 'android', 'app', 'src', flavorName(t.id), 'AndroidManifest.xml'), flavorManifest(t));
        const icon = join(app, 'android', 'app', 'src', flavorName(t.id), NOTIFICATION_ICON.to);
        mkdirSync(join(icon, '..'), { recursive: true });
        copyFileSync(join(app, flavorAssetDir(flavorName(t.id)), 'icons', NOTIFICATION_ICON.from), icon);
      }
    } else console.log('no android/ folder yet: run `flutter create . --platforms=android` in apps/realtor_app, then re-run');
    console.log(`flavors: ${flavors.join(', ')}
next, in apps/realtor_app:
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create --flavors ${flavors.join(',')}
  flutter build apk --flavor ${flavors[0]}`);
    break;
  }
  case 'firebase-config': {
    // In Cloud Shell, after `prepare <id>` (or `flavors`), signed in with
    // the firebase CLI: firebase-config <id> <dev|stage|prod> [--flavor]
    const [id, env] = args.filter((a) => !a.startsWith('--'));
    const flags = new Set(args.filter((a) => a.startsWith('--')));
    if (!id || !env) usage();
    const t = loadValid(id);
    const project = t.firebase.projects[env];
    if (!project) throw new Error(`tenant ${id} has no ${env} project`);
    const run = (cmd: string) => JSON.parse(execSync(`firebase ${cmd} --project ${project} --json`, { encoding: 'utf8' })).result;
    const ids = pickApps(run('apps:list'), t.apps.androidId, t.apps.iosId);
    if (!ids.android && !ids.ios) throw new Error(`no Android or iOS app for ${t.apps.androidId} / ${t.apps.iosId} in ${project}`);
    const out: MobileFirebase = { projectId: project, messagingSenderId: '' };
    if (ids.android) Object.assign(out, fromGoogleServices(run(`apps:sdkconfig ANDROID ${ids.android}`).fileContents, t.apps.androidId));
    if (ids.ios) {
      const ios = fromServiceInfoPlist(run(`apps:sdkconfig IOS ${ids.ios}`).fileContents);
      out.ios = { appId: ios.appId, apiKey: ios.apiKey, bundleId: ios.bundleId };
      out.messagingSenderId ||= ios.messagingSenderId;
    }
    const dir = flags.has('--flavor') ? flavorAssetDir(flavorName(t.id)) : 'assets/tenant';
    const file = join(repoRoot(), 'apps', 'realtor_app', dir, 'firebase.json');
    writeFileSync(file, JSON.stringify(out, null, 2));
    console.log(`wrote ${relative(repoRoot(), file)} (${env}: ${project}${ids.android ? ', android' : ''}${ids.ios ? ', ios' : ''})`);
    break;
  }
  case 'release': {
    const [id] = args.filter((a) => !a.startsWith('--'));
    const opt = (name: string) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
    const dryRun = args.includes('--dry-run');
    const track = (opt('track') ?? 'internal') as Track;
    const status = (opt('status') ?? 'completed') as 'completed' | 'draft';
    if (!id || !(track in TRACKS) || !['completed', 'draft'].includes(status)) usage();
    const t = loadValid(id);
    const project: string | undefined = t.firebase.projects.prod;
    if (!project) throw new Error(`tenant ${id} has no prod project`);
    const root = repoRoot();
    const listing = storeListing(t);
    const bad = listingProblems(listing);
    if (bad.length) {
      console.error(`✗ store listing:\n${bad.map((b) => `  - ${b}`).join('\n')}\n  set store.listing in tenants/${id}.json`);
      process.exit(1);
    }
    const tag = execSync('git rev-parse --short HEAD', { cwd: root, encoding: 'utf8' }).trim();
    const build = versionCode(new Date());
    const language = t.store?.language ?? 'en-GB';
    const notes = opt('notes') ?? `Build ${tag}`;
    const allFlavors = readdirSync(join(root, 'tenants')).filter((f) => f.endsWith('.json')).map((f) => flavorName(basename(f, '.json')));
    const steps = releaseSteps(id, allFlavors, build);
    console.log(`release ${id} (${t.apps.androidId}) → Play ${track} track (${status}), commit ${tag}, version code ${build}`);
    console.log(`  listing (${language}): "${listing.title}" · "${listing.shortDescription}"`);
    if (dryRun) {
      for (const s of steps) console.log(`\n# ${s.title}${s.skipIfExists ? ` (skipped if ${s.skipIfExists} exists)` : ''}\n${shellLine({ ...s, part: 'web' })}`);
      console.log(`\n# Secrets read from ${project}: ${Object.values(RELEASE_SECRETS).join(', ')} (never printed)`);
      console.log(`# Then: upload the bundle from ${BUNDLE_DIR}, put it on ${TRACKS[track]}, update the listing, commit the edit`);
      console.log(`\n# Full description:\n${listing.fullDescription}`);
      break;
    }
    const dirty = uncommitted(root);
    if (dirty.length) {
      console.error(`✗ uncommitted changes in ${dirty.join(', ')}: the bundle is built from the commit, so commit or stash them first`);
      process.exit(1);
    }
    const missing = ['gcloud', 'firebase', 'flutter', 'dart'].filter((bin) => spawnSync('which', [bin]).status !== 0);
    if (missing.length) {
      console.error(`✗ not on PATH: ${missing.join(', ')}`);
      process.exit(1);
    }
    const secret = (name: string): Buffer => {
      const r = spawnSync('gcloud', ['secrets', 'versions', 'access', 'latest', `--secret=${name}`, `--project=${project}`], { stdio: ['ignore', 'pipe', 'pipe'] });
      if (r.status !== 0) throw new Error(`could not read secret "${name}" in ${project} (see docs/store-release.md): ${String(r.stderr).split('\n')[0]}`);
      return r.stdout;
    };
    // Secrets live only in this folder (0700/0600) for the build, then go.
    const tmp = mkdtempSync(join(tmpdir(), 'tenant-release-'));
    try {
      const keystore = join(tmp, 'upload.jks');
      writeFileSync(keystore, Buffer.from(secret(RELEASE_SECRETS.keystore).toString('utf8').trim(), 'base64'), { mode: 0o600 });
      const env = signingEnv(keystore, secret(RELEASE_SECRETS.keystorePassword).toString('utf8').trim());
      for (const s of steps) {
        if (s.skipIfExists && existsSync(join(root, s.skipIfExists))) continue;
        console.log(`\n▶ ${s.title}\n  ${s.argv.join(' ')}`);
        const r = spawnSync(s.argv[0], s.argv.slice(1), { cwd: join(root, s.cwd), env: { ...process.env, ...env }, stdio: 'inherit' });
        if (r.status !== 0) throw new Error(`"${s.title}" failed`);
      }
      const found = pickBundle(readdirSync(join(root, BUNDLE_DIR), { recursive: true }).map(String), id);
      if (!found) throw new Error(`no ${flavorName(id)} release bundle under ${BUNDLE_DIR}`);
      const bundle = readFileSync(join(root, BUNDLE_DIR, found));
      console.log(`\n▶ Google Play: ${(bundle.length / 1e6).toFixed(1)} MB bundle to the ${track} track`);
      const sa = JSON.parse(secret(RELEASE_SECRETS.serviceAccount).toString('utf8'));
      const token = await playToken(sa, new Date());
      const code = await publishToPlay(token, { packageName: t.apps.androidId, bundle, track, listing, language, notes, status });
      console.log(`\n✓ ${t.apps.androidId} version ${code} is on the ${track} track${status === 'draft' ? ' as a draft: roll it out in the Play Console' : ''}`);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
      // `flavors` fills the pubspec's flavor block, which stays empty in git.
      spawnSync('git', ['checkout', '--', 'apps/realtor_app/pubspec.yaml'], { cwd: root });
    }
    break;
  }
  case 'deploy': {
    // In Cloud Shell, from the repo: deploy <id> <dev|stage|prod>
    //   [--only=functions,images,infra,web] [--billing=XXXXXX-XXXXXX-XXXXXX] [--dry-run] [--yes]
    const [id, env] = args.filter((a) => !a.startsWith('--'));
    const opt = (name: string) => args.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
    const flag = (name: string) => args.includes(`--${name}`);
    if (!id || !(ENVS as readonly string[]).includes(env)) usage();
    const t = loadValid(id);
    const project: string | undefined = t.firebase.projects[env];
    if (!project) throw new Error(`tenant ${id} has no ${env} project`);
    const root = repoRoot();
    const parts = parseParts(opt('only'));
    const git = (c: string) => execSync(`git ${c}`, { cwd: root, encoding: 'utf8' }).trim();
    const tag = git('rev-parse --short HEAD');
    const dryRun = flag('dry-run');
    // Images are tagged with the commit, so they must be built from exactly it.
    const dirty = uncommitted(root);
    if (parts.includes('images') && !dryRun && dirty.length) {
      console.error(`✗ uncommitted changes in ${dirty.join(', ')}: commit or stash them first (images are tagged with the commit)`);
      process.exit(1);
    }
    let billing: string | undefined;
    if (parts.includes('infra')) {
      const raw =
        opt('billing') ??
        (dryRun ? 'XXXXXX-XXXXXX-XXXXXX' : execSync(`gcloud billing projects describe ${project} --format="value(billingAccountName)"`, { encoding: 'utf8' }));
      billing = dryRun ? raw : (parseBilling(raw) ?? undefined);
      if (!billing) {
        console.error(`✗ no billing account for ${project} ("${raw.trim()}"); pass --billing=XXXXXX-XXXXXX-XXXXXX`);
        process.exit(1);
      }
    }
    const steps = deploySteps({ id, env: env as Env, project, region: t.firebase.region, tag, billing, parts });
    const shown = shellLine;
    console.log(`deploy ${id} → ${project} (${env}), commit ${tag}: ${parts.join(', ')}`);
    if (dryRun) {
      for (const s of steps) console.log(`\n# ${s.title}${s.skipIfExists ? ` (skipped if ${s.skipIfExists} exists)` : ''}\n${shown(s)}`);
      break;
    }
    const missing = [...new Set(steps.map((s) => s.argv[0]))].filter((bin) => spawnSync('which', [bin]).status !== 0);
    if (missing.length) {
      console.error(`✗ not on PATH: ${missing.join(', ')}`);
      process.exit(1);
    }
    for (const s of steps) {
      if (s.skipIfExists && existsSync(join(root, s.skipIfExists))) continue;
      console.log(`\n▶ ${s.title}\n  ${shown(s)}`);
      if (s.retryFunctions) {
        // Shown live and kept, to find what Google's write quota made fail.
        let r = await runTee(s.argv, join(root, s.cwd), s.env);
        for (let round = 1; r.status !== 0 && round <= 3; round++) {
          const failed = failedFunctions(r.output);
          if (!failed.length) break;
          console.log(`\n↻ ${failed.length} functions failed (usually the API's write quota); in a minute, again in sixes (round ${round} of 3)`);
          await new Promise((done) => setTimeout(done, process.env.DEPLOY_RETRY_MS ? Number(process.env.DEPLOY_RETRY_MS) : 60_000));
          let output = '', status = 0;
          for (const only of functionBatches(failed)) {
            const b = await runTee([s.argv[0], 'deploy', '--only', only, ...s.argv.slice(s.argv.indexOf('--project'))], join(root, s.cwd), s.env);
            output += b.output;
            if (b.status !== 0) status = b.status;
          }
          r = { status, output };
        }
        if (r.status !== 0) {
          console.error(`\n✗ "${s.title}" failed. Fix it, then carry on with: tenant deploy ${id} ${env} --only=${parts.slice(parts.indexOf(s.part)).join(',')}`);
          process.exit(1);
        }
        continue;
      }
      const r = spawnSync(s.argv[0], s.argv.slice(1), {
        cwd: join(root, s.cwd),
        env: { ...process.env, ...s.env },
        stdio: s.checkPlan ? ['ignore', 'pipe', 'inherit'] : 'inherit',
        encoding: 'utf8',
        maxBuffer: 256 * 1024 * 1024,
      });
      if (r.status !== 0) {
        if (s.hint) console.error(`\n✗ "${s.title}" failed. ${s.hint}`);
        else console.error(`\n✗ "${s.title}" failed. Fix it, then carry on with: tenant deploy ${id} ${env} --only=${parts.slice(parts.indexOf(s.part)).join(',')}`);
        process.exit(1);
      }
      if (s.checkPlan) {
        const plan = JSON.parse(r.stdout);
        const problems = planProblems(plan, imageRepo(project, t.firebase.region));
        if (problems.length) {
          console.error(`✗ refusing to apply this plan:\n${problems.map((p) => `  - ${p}`).join('\n')}`);
          process.exit(1);
        }
        const n = planSummary(plan);
        console.log(`  plan: ${n.add} to add, ${n.change} to change, ${n.replace} to replace, ${n.destroy} to destroy`);
        if (!flag('yes')) {
          const rl = createInterface({ input: process.stdin, output: process.stdout });
          const answer = await rl.question(`  Apply to ${project} (${env})? [y/N] `);
          rl.close();
          if (answer.trim().toLowerCase() !== 'y') {
            console.log('  not applied');
            process.exit(1);
          }
        }
      }
    }
    console.log(`\n✓ deployed ${id} to ${project} at ${tag}`);
    break;
  }
  default:
    usage();
}
