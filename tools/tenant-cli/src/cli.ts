#!/usr/bin/env node
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { join, basename } from 'node:path';
import { validateTenants, repoRoot } from './validate.ts';
import { tenantCss } from './css.ts';

const [cmd, ...args] = process.argv.slice(2);

function usage(): never {
  console.log(`tenant <command>

  validate [id...]   Check tenant files against the schema, assets and colour contrast
  css <id>           Write build/tokens/<id>.css for the share pages
  prepare <id>       Copy the tenant file and brand assets into apps/realtor_app/assets/tenant

Coming later: create <id>, deploy <id> <env>, build <id> <platform>`);
  process.exit(cmd ? 1 : 0);
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
  case 'prepare': {
    const id = args[0];
    if (!id) usage();
    const bad = validateTenants(repoRoot(), [id]).find((r) => r.errors.length);
    if (bad) {
      console.error(`✗ ${bad.file} is invalid; run "tenant validate ${id}"`);
      process.exit(1);
    }
    const root = repoRoot();
    const t = JSON.parse(readFileSync(join(root, 'tenants', `${id}.json`), 'utf8'));
    const out = join(root, 'apps', 'realtor_app', 'assets', 'tenant');
    rmSync(out, { recursive: true, force: true });
    mkdirSync(out, { recursive: true });
    writeFileSync(join(out, '.gitkeep'), '');
    writeFileSync(join(out, 'tenant.json'), JSON.stringify(t, null, 2));
    const logos = Object.values<string>(t.brand.logo).filter((p) => !p.endsWith('.ai'));
    for (const p of new Set([...logos, t.brand.appIcon])) copyFileSync(join(root, p), join(out, basename(p)));
    console.log(`prepared ${id} → apps/realtor_app/assets/tenant (${logos.length} logo file(s))`);
    break;
  }
  default:
    usage();
}
