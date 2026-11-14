import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';
import { Ajv2020 } from 'ajv/dist/2020.js';
import addFormatsModule from 'ajv-formats';
import { contrastProblems } from './contrast.ts';
import { fontProblems } from './fonts.ts';

// ajv-formats ships CJS; under NodeNext the callable is on .default.
const addFormats = ((addFormatsModule as any).default ?? addFormatsModule) as (ajv: Ajv2020) => Ajv2020;

export interface Result {
  file: string;
  errors: string[];
}

export function repoRoot(): string {
  return join(import.meta.dirname, '..', '..', '..');
}

function collectAssetPaths(node: unknown, out: string[] = []): string[] {
  if (typeof node === 'string' && node.startsWith('brand/')) out.push(node);
  else if (node && typeof node === 'object') for (const v of Object.values(node)) collectAssetPaths(v, out);
  return out;
}

export function validateTenants(root = repoRoot(), only?: string[]): Result[] {
  const schema = JSON.parse(readFileSync(join(root, 'tenants/schema/tenant.schema.json'), 'utf8'));
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  addFormats(ajv);
  const check = ajv.compile(schema);

  const dir = join(root, 'tenants');
  const files = readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .filter((f) => !only?.length || only.includes(basename(f, '.json')));

  return files.map((f) => {
    const errors: string[] = [];
    let data: any = null;
    try {
      data = JSON.parse(readFileSync(join(dir, f), 'utf8'));
    } catch (e) {
      return { file: f, errors: [`not valid JSON: ${(e as Error).message}`] };
    }
    if (!check(data as object)) {
      for (const e of check.errors ?? []) errors.push(`${e.instancePath || '/'} ${e.message}`);
      return { file: f, errors };
    }
    if (data.id !== basename(f, '.json')) errors.push(`id "${data.id}" must match the file name`);
    for (const p of [...collectAssetPaths(data.brand), ...collectAssetPaths(data.home)]) {
      if (!existsSync(join(root, p))) errors.push(`missing asset ${p}`);
      // <text> renders with whatever fonts the build machine has; logos must be outlined.
      else if (p.endsWith('.svg') && /<text[\s>]/.test(readFileSync(join(root, p), 'utf8')))
        errors.push(`${p} uses <text>: convert the lettering to paths`);
    }
    errors.push(...contrastProblems(data.brand.colors));
    errors.push(...fontProblems(root, data));
    return { file: f, errors };
  });
}
