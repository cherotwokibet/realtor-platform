import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { repoRoot } from '../src/validate.ts';

// Rule 1 of the README: nothing about a realtor lives in code. A second
// realtor must run with zero code changes, so no tenant's identifiers may
// appear in the apps, packages, functions or tooling source.
const codeDirs = ['apps/realtor_app/lib', 'packages/core/lib', 'packages/tokens/lib', 'packages/ui/lib', 'functions/src', 'tools/tenant-cli/src'];

function files(dir: string): string[] {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? files(p) : /\.(dart|ts)$/.test(f) ? [p] : [];
  });
}

function identifiers(t: any): string[] {
  return [
    t.id,
    t.name,
    ...Object.values(t.domains),
    t.apps.androidId,
    t.apps.iosId,
    ...Object.values(t.firebase.projects),
    t.contact.email,
  ].filter((s): s is string => typeof s === 'string' && s.length > 3);
}

test('no tenant identifiers in product code', () => {
  const root = repoRoot();
  const tenants = readdirSync(join(root, 'tenants'))
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(readFileSync(join(root, 'tenants', f), 'utf8')));
  assert.ok(tenants.length >= 2);
  const hits: string[] = [];
  for (const file of codeDirs.flatMap((d) => files(join(root, d)))) {
    const src = readFileSync(file, 'utf8').toLowerCase();
    for (const t of tenants)
      for (const s of identifiers(t)) if (src.includes(s.toLowerCase())) hits.push(`${relative(root, file)}: "${s}" (${t.id})`);
  }
  assert.deepEqual(hits, [], 'move these values into tenants/<id>.json');
});
