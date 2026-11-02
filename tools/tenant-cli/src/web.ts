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

// Old links used hash URLs (app.<domain>/#/listing/x). Rewrite them to the
// path before Flutter starts, so go_router sees /listing/x (P3-s07).
const HASH_REDIRECT = `<script>if(location.hash.indexOf('#/')===0)history.replaceState(null,'',location.hash.slice(1));</script>`;

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
  if (!out.includes(HASH_REDIRECT)) out = out.replace('</head>', `  ${HASH_REDIRECT}\n</head>`);
  return withLoadingScreen(out, t, t.tagline ?? '');
}

/**
 * The admin's web shell: the tenant's name, kept out of search engines
 * (it is behind a login), and the same loading screen. Pair with
 * [ADMIN_ROBOTS] as web/robots.txt.
 */
export function patchAdminIndexHtml(html: string, t: any): string {
  let out = html
    .replace(/<html[^>]*>/, `<html lang="${t.locale.default.split('-')[0]}">`)
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(t.name)} admin</title>`);
  out = setMeta(out, 'name', 'description', `Staff admin for ${t.name}.`);
  out = setMeta(out, 'name', 'apple-mobile-web-app-title', `${t.name} admin`);
  out = setMeta(out, 'name', 'theme-color', t.brand.colors.primary);
  out = setMeta(out, 'name', 'robots', 'noindex, nofollow');
  return withLoadingScreen(out, t, 'Admin');
}

export const ADMIN_ROBOTS = 'User-agent: *\nDisallow: /\n';

/**
 * Plain HTML shown while Flutter starts (P3-s01): the tenant's name in its
 * colours, painted with the first bytes, so a phone on 4G sees the brand at
 * once and Lighthouse has a contentful paint to measure (Flutter draws on a
 * canvas it cannot). Removed on Flutter's first frame.
 */
function withLoadingScreen(html: string, t: any, line: string): string {
  if (html.includes('id="loading"')) return html;
  const c = t.brand.colors;
  const style = `<style>#loading{position:fixed;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;pointer-events:none;background:${c.background};color:${c.primary};font:600 24px/1.3 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;text-align:center;padding:24px}#loading small{font:400 15px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;color:${c.textMuted}}</style>`;
  const div = `<div id="loading" aria-hidden="true">${esc(t.name)}${line ? `<small>${esc(line)}</small>` : ''}</div>`;
  // Gone on Flutter's first frame; after 10 s at the latest, so it can never cover the app.
  const remove = `<script>(function(){function go(){var e=document.getElementById('loading');if(e)e.remove();}window.addEventListener('flutter-first-frame',go);setTimeout(go,10000);})();</script>`;
  return html.replace(/<head>/, `<head>\n  ${style}`).replace(/<body>/, `<body>\n  ${div}\n  ${remove}`);
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
