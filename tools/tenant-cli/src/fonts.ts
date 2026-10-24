import { existsSync } from 'node:fs';
import { join } from 'node:path';

/** Weights the theme uses. Every bundled family ships all four. */
export const fontWeights = { 400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold' } as const;

export interface FontFile {
  family: string;
  weight: number;
  /** Repo-relative source, e.g. fonts/Inter/Inter-SemiBold.ttf */
  source: string;
  /** File name inside assets/tenant/fonts/ */
  file: string;
}

export function fontDir(family: string): string {
  return family.replace(/\s+/g, '');
}

/** The files a tenant needs: display and body families, deduplicated. */
export function tenantFontFiles(tenant: any): FontFile[] {
  const families = [...new Set<string>([tenant.brand.fonts.display, tenant.brand.fonts.body])];
  return families.flatMap((family) =>
    Object.entries(fontWeights).map(([w, name]) => {
      const file = `${fontDir(family)}-${name}.ttf`;
      return { family, weight: Number(w), source: `fonts/${fontDir(family)}/${file}`, file };
    }),
  );
}

export function fontProblems(root: string, tenant: any): string[] {
  return tenantFontFiles(tenant)
    .filter((f) => !existsSync(join(root, f.source)))
    .map((f) => `font "${f.family}" ${f.weight} is not bundled: add ${f.source} (see fonts/README.md)`);
}
