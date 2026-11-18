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

// Push alerts are phone-only until a VAPID key exists (P4-s03): keep
// FlutterFire from downloading the messaging SDK when the web app starts.
const SKIP_WEB_MESSAGING = `<script>window.flutterfire_ignore_scripts=['messaging'];</script>`;

/**
 * [fonts] are the tenant's bundled font assets (`fonts.json`), fetched by
 * the app before its first frame and so preloaded with the engine.
 */
export function patchIndexHtml(html: string, t: any, fonts: string[] = []): string {
  let out = html
    .replace(/<html[^>]*>/, `<html lang="${t.locale.default.split('-')[0]}">`)
    .replace(/<title>[^<]*<\/title>/, `<title>${esc(t.name)}</title>`);
  out = setMeta(out, 'name', 'description', webDescription(t));
  out = setMeta(out, 'name', 'apple-mobile-web-app-title', t.name);
  out = setMeta(out, 'name', 'theme-color', t.brand.colors.primary);
  out = setMeta(out, 'property', 'og:title', t.name);
  out = setMeta(out, 'property', 'og:description', webDescription(t));
  out = setMeta(out, 'property', 'og:image', 'og.png');
  if (!out.includes(SKIP_WEB_MESSAGING)) out = out.replace('</head>', `  ${SKIP_WEB_MESSAGING}\n</head>`);
  if (!out.includes(HASH_REDIRECT)) out = out.replace('</head>', `  ${HASH_REDIRECT}\n</head>`);
  return withStartupPreloads(withAppSkeleton(out, t), fonts);
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

/** The customer app's web/robots.txt. Without one, Hosting answers
 * /robots.txt with the app's index.html, which crawlers read as invalid. */
export const APP_ROBOTS = 'User-agent: *\nAllow: /\n';

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

/**
 * The customer app's loading screen (P3-s01): instead of plain words, the
 * outline of the page it is about to show (the logo, the search bar, the
 * filter pills and two home cards, gently shimmering), painted with the
 * first bytes of HTML. Visitors see the site at once and the wait reads as
 * the page filling in, as on the big portals. Removed on Flutter's first
 * frame. Replaces the older text-only screen in an existing index.html.
 */
export function withAppSkeleton(html: string, t: any): string {
  if (html.includes('id="loading" class="sk"')) return html;
  // An index.html from before: take the text-only screen out first.
  let out = html
    .replace(/\s*<style>#loading\{[^<]*<\/style>/, '')
    .replace(/\s*<div id="loading"[^>]*>.*?<\/div>/, '')
    .replace(/\s*<script>\(function\(\)\{function go\(\)\{var e=document\.getElementById\('loading'\)[^<]*<\/script>/, '');
  const c = t.brand.colors;
  const line = t.tagline ?? '';
  const style =
    `<style>#loading{position:fixed;inset:0;z-index:9;overflow:hidden;pointer-events:none;background:${c.background};font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}` +
    `#loading .sk-in{max-width:1100px;margin:0 auto;padding:0 16px}` +
    `#loading .sk-top{display:flex;align-items:center;justify-content:space-between;height:64px;border-bottom:1px solid ${c.border};padding:0 16px}` +
    `#loading .sk-top img{height:44px}` +
    `#loading .sk-b,#loading .sk-c i{background:linear-gradient(90deg,${c.surfaceAlt} 25%,${c.surface} 50%,${c.surfaceAlt} 75%);background-size:200% 100%;animation:sk 1.2s ease-in-out infinite;border-radius:${t.brand.radius.sm}px;display:block}` +
    `#loading .sk-login{width:84px;height:36px;border-radius:999px}` +
    `#loading .sk-search{height:44px;margin:12px 0 8px}` +
    `#loading .sk-pills{display:flex;gap:8px;margin-bottom:16px}#loading .sk-pills .sk-b{height:32px;width:96px;border-radius:999px}` +
    `#loading .sk-c{margin-bottom:16px;border:1px solid ${c.border};border-radius:${t.brand.radius.md}px;overflow:hidden}` +
    `#loading .sk-c i.p{height:200px;border-radius:0}#loading .sk-c i{height:14px;margin:12px}#loading .sk-c i.w6{width:60%}#loading .sk-c i.w4{width:40%}` +
    `#loading .sk-name{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}` +
    `@keyframes sk{0%{background-position:200% 0}100%{background-position:-200% 0}}@media (prefers-reduced-motion:reduce){#loading .sk-b,#loading .sk-c i{animation:none}}</style>`;
  const card = '<div class="sk-c"><i class="p"></i><i class="w6"></i><i class="w4"></i></div>';
  const div =
    `<div id="loading" class="sk" aria-hidden="true">` +
    `<div class="sk-top"><img src="assets/assets/tenant/logo-horizontal.png" alt=""><span class="sk-b sk-login"></span></div>` +
    `<div class="sk-in"><span class="sk-b sk-search"></span><div class="sk-pills"><span class="sk-b"></span><span class="sk-b"></span><span class="sk-b"></span></div>${card}${card}</div>` +
    `<p class="sk-name">${esc(t.name)}${line ? `<small>${esc(line)}</small>` : ''}</p></div>`;
  // Gone on Flutter's first frame; after 15 s at the latest, so it can never cover the app.
  const remove = `<script>(function(){function go(){var e=document.getElementById('loading');if(e)e.remove();}window.addEventListener('flutter-first-frame',go);setTimeout(go,15000);})();</script>`;
  return out.replace(/<head>/, `<head>\n  ${style}`).replace(/<body>/, `<body>\n  ${div}\n  ${remove}`);
}

/**
 * The app's first frame waits on a chain: flutter_bootstrap.js, then the
 * engine and app code, then the tenant file, fonts and Hosting's Firebase
 * settings, then the Firebase SDK. Requesting them all with the HTML puts
 * them on the wire at once (P3-s01). The WebAssembly files are preloaded
 * only where the browser will use them (WasmGC, as flutter.js checks), so
 * older browsers on the JavaScript build download nothing twice.
 */
export function withStartupPreloads(html: string, fonts: string[]): string {
  if (html.includes('id="startup-preload"')) return html;
  const fetchLink = (href: string) => `<link rel="preload" href="${esc(href)}" as="fetch" crossorigin="anonymous">`;
  const links = [
    // Flutter serves asset <key> at assets/<key>.
    ...['assets/tenant/tenant.json', 'assets/tenant/fonts.json', ...fonts].map((key) => fetchLink(`assets/${key}`)),
    fetchLink('/__/firebase/init.json'),
    // The live homes (the listingIndex function, CDN-cached), fetched while the app downloads.
    fetchLink('/api/listings.json'),
    // The loading screen's logo, before anything else on the page.
    '<link rel="preload" href="assets/assets/tenant/logo-horizontal.png" as="image">',
    // The engine and Firebase SDK come from gstatic, the fallback font from fonts.gstatic.
    '<link rel="preconnect" href="https://www.gstatic.com" crossorigin>',
    '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>',
  ];
  const wasm = `<script id="startup-preload">(function(){try{if(!WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,95,1,120,0])))return;[['modulepreload','main.dart.mjs'],['preload','main.dart.wasm']].forEach(function(x){var l=document.createElement('link');l.rel=x[0];l.href=x[1];if(x[0]==='preload'){l.as='fetch';l.crossOrigin='anonymous';}document.head.appendChild(l);});}catch(e){}})();</script>`;
  return html.replace(/<meta charset="UTF-8">/, (m) => `${m}
  ${[...links, wasm].join('\n  ')}`);
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

/**
 * The app site's /.well-known/assetlinks.json: lets the Android app open
 * emailed sign-in links (flavorManifest). Lists the store certificate and
 * test builds' certificates; empty, and so claiming nothing, until known.
 */
export function appAssetLinks(t: any): string {
  const certs = [...(t.apps.androidCertSha256 ?? []), ...(t.apps.testCerts ?? []).map((c: any) => c.sha256)];
  if (!certs.length) return '[]\n';
  return JSON.stringify(
    [
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: { namespace: 'android_app', package_name: t.apps.androidId, sha256_cert_fingerprints: [...new Set(certs)] },
      },
    ],
    null,
    2,
  ) + '\n';
}
