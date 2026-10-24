// Emits CSS custom properties from a tenant file, for the Jaspr share pages.
// The Dart side (packages/tokens) produces the same values for Flutter.

const kebab = (s: string) => s.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());

export function tenantCss(t: any): string {
  const b = t.brand;
  const lines: string[] = [];
  for (const [k, v] of Object.entries<string>(b.colors)) lines.push(`  --color-${kebab(k)}: ${v};`);
  for (const [k, v] of Object.entries<number>(b.typeScale)) lines.push(`  --text-${kebab(k)}: ${v / 16}rem;`);
  for (const [k, v] of Object.entries<number>(b.radius)) lines.push(`  --radius-${k}: ${v}px;`);
  lines.push(`  --space: ${b.spacingBase}px;`);
  lines.push(`  --font-display: "${b.fonts.display}", system-ui, sans-serif;`);
  lines.push(`  --font-body: "${b.fonts.body}", system-ui, sans-serif;`);
  return `/* Generated from tenants/${t.id}.json. Do not edit. */\n:root {\n${lines.join('\n')}\n}\n`;
}
