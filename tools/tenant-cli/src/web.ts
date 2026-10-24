// Per-tenant web shell: `flutter create` writes index.html and manifest.json
// with "realtor_app" / "A new Flutter project." (the SEO bug in the audit).
// `tenant web <id>` rewrites them from the tenant file. Run it after the
// launcher-icon and splash tools, which also edit index.html.

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function webDescription(t: any): string {
  return t.tagline ? `${t.name}: ${t.tagline}. Homes to rent and buy in Kenya.` : `${t.name}: homes to rent and buy in Kenya.`;
}

function setMeta(html: string, attr: 'name' | 'property', key: string, content: string): string {
  const tag = `<meta ${attr}="${key}" content="${esc(content)}">`;
  const re = new RegExp(`<meta ${attr}="${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"[^>]*>`);
  return re.test(html) ? html.replace(re, tag) : html.replace('</head>', `  ${tag}\n</head>`);
}

export function patchIndexHtml(html: string, t: any): string {
  let out = html
    .replace(/<html[^>]*>/, `<html lang="${t.locale.default.split('-')[0]}">`)
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(t.name)}</title>`);
  out = setMeta(out, 'name', 'description', webDescription(t));
  out = setMeta(out, 'name', 'apple-mobile-web-app-title', t.name);
  out = setMeta(out, 'name', 'theme-color', t.brand.colors.primary);
  out = setMeta(out, 'property', 'og:title', t.name);
  out = setMeta(out, 'property', 'og:description', webDescription(t));
  out = setMeta(out, 'property', 'og:image', 'og.png');
  return out;
}

export function patchManifest(json: string, t: any, shortName: string): string {
  const m = JSON.parse(json);
  Object.assign(m, {
    name: t.name,
    short_name: shortName,
    description: webDescription(t),
    theme_color: t.brand.colors.primary,
    background_color: t.brand.colors.background,
    lang: t.locale.default,
    start_url: '/',
  });
  return JSON.stringify(m, null, 2) + '\n';
}
