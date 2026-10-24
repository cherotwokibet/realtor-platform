// WCAG 2.x contrast helpers. Used to stop a tenant shipping unreadable colours.

export function luminance(hex: string): number {
  const v = hex.replace('#', '');
  const ch = [0, 2, 4].map((i) => parseInt(v.slice(i, i + 2), 16) / 255);
  const lin = ch.map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}

export function contrast(a: string, b: string): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/** [foreground, background, minimum ratio]. 4.5 = WCAG AA body text, 3 = large text / UI parts. */
export const REQUIRED_PAIRS: ReadonlyArray<readonly [string, string, number]> = [
  ['onPrimary', 'primary', 4.5],
  ['onAccent', 'accent', 4.5],
  ['ink', 'surface', 4.5],
  ['text', 'surface', 4.5],
  ['textMuted', 'surface', 4.5],
  ['accentText', 'surface', 4.5],
  ['primary', 'surface', 4.5],
  ['primary', 'primarySoft', 4.5],
  ['error', 'surface', 4.5],
  ['success', 'surface', 4.5],
  ['info', 'surface', 4.5],
  ['text', 'background', 4.5],
];

export function contrastProblems(colors: Record<string, string>): string[] {
  const out: string[] = [];
  for (const [fg, bg, min] of REQUIRED_PAIRS) {
    const r = contrast(colors[fg], colors[bg]);
    if (r < min) out.push(`${fg} on ${bg} is ${r.toFixed(2)}:1, needs ${min}:1`);
  }
  return out;
}
