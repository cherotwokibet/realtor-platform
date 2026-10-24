#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync, readdirSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';
import { validateTenants, repoRoot } from './validate.ts';
import { tenantCss } from './css.ts';
import { generateIcons } from './icons.ts';
import { flutterConfigs } from './flutter-config.ts';
import { tenantFontFiles } from './fonts.ts';
import {
  flavorName,
  flavorAssetDir,
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
  prepare <id>       Generate icons, then copy the tenant file, logos and fonts into apps/realtor_app/assets/tenant
  flavors [id...]    One Android flavor per tenant (default: all): assets/flavors/<flavor>/, flavor-only
                     pubspec assets, per-flavor icon + splash configs, productFlavors in android/app

Coming later: create <id>, deploy <id> <env>, build <id> <platform>, iOS flavors`);
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

function resetDir(dir: string): void {
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, '.gitkeep'), '');
}

/** Tenant file, logos, fonts (+ manifest) and icon inputs, under apps/realtor_app/<rel>. */
async function writeAppAssets(root: string, t: any, rel: string): Promise<void> {
  const r = await generateIcons(root, t);
  const out = join(root, 'apps', 'realtor_app', rel);
  resetDir(out);
  writeFileSync(join(out, 'tenant.json'), JSON.stringify(t, null, 2));
  // Fixed file names: the app refers to these, never to a realtor's own names.
  for (const f of ['logo-horizontal.png', 'logo-horizontal-reverse.png', 'logo-stacked.png', 'mark.png']) {
    copyFileSync(join(r.outDir, f), join(out, f));
  }
  // Fonts: the app registers every entry of fonts.json before the first frame.
  mkdirSync(join(out, 'fonts'), { recursive: true });
  const fonts = tenantFontFiles(t);
  for (const f of fonts) copyFileSync(join(root, f.source), join(out, 'fonts', f.file));
  writeFileSync(
    join(out, 'fonts.json'),
    JSON.stringify(fonts.map((f) => ({ family: f.family, weight: f.weight, asset: `${rel}/fonts/${f.file}` })), null, 2),
  );
  // Launcher icon + splash inputs live in a subfolder, which Flutter does not bundle.
  mkdirSync(join(out, 'icons'), { recursive: true });
  for (const f of r.files.filter((f) => f.endsWith('.png'))) copyFileSync(join(r.outDir, f), join(out, 'icons', f));
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
    await writeAppAssets(root, t, 'assets/tenant');
    const app = join(root, 'apps', 'realtor_app');
    const cfg = flutterConfigs(t);
    writeFileSync(join(app, 'flutter_launcher_icons.yaml'), cfg.launcherIcons);
    writeFileSync(join(app, 'flutter_native_splash.yaml'), cfg.nativeSplash);
    console.log(`prepared ${id} → apps/realtor_app/assets/tenant (icons in brand/${id}/generated)`);
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
    } else console.log('no android/ folder yet: run `flutter create . --platforms=android` in apps/realtor_app, then re-run');
    console.log(`flavors: ${flavors.join(', ')}
next, in apps/realtor_app:
  dart run flutter_launcher_icons
  dart run flutter_native_splash:create --flavors ${flavors.join(',')}
  flutter build apk --flavor ${flavors[0]}`);
    break;
  }
  default:
    usage();
}
