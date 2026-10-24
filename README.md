# Realtor Platform

A white-label system for Kenyan real-estate agencies. Each realtor gets their own branded app (Android, iOS, web), admin/CRM and SEO share pages, built from **one codebase** and **one tenant file**.

Tenant #1: **Realtime Estates Ltd** (Nairobi). Owner: Actify Software Solutions.

## Rules

1. Nothing about a realtor lives in code. Brand, contacts, domains, features and IDs come from `tenants/<id>.json` and `brand/<id>/`. No hex colours in widgets.
2. Money, approval, verification and commission logic runs in Cloud Functions. Clients read; they never set status, verification, payment results or commissions.
3. No service-account JSON keys, ever. CI deploys through Workload Identity.
4. Every tenant file must pass `tenant validate` (schema, assets, WCAG contrast) before merge.

## Layout

```
apps/realtor_app     Flutter customer app: Android, iOS, web
apps/admin           Flutter web admin / CRM                     (P5)
apps/share_pages     Jaspr SSR listing/area/agent pages for SEO  (P3)
packages/core        tenant config, models, money (pure Dart)
packages/tokens      tenant -> design tokens + CSS (pure Dart)
packages/ui          Flutter theme + shared widgets
functions/           Cloud Functions, TypeScript, 2nd gen
tenants/             one JSON per realtor + JSON Schema
brand/               logos and icons per realtor
fonts/               bundled font families (OFL), copied per tenant by prepare
tools/tenant-cli     validate / css / prepare (create, deploy, build later)
infra/terraform      per-tenant Firebase projects: module + root config (never applied by CI)
```

## First-time setup (Windows)

Needs: Flutter stable (3.35+), Node 22, Git, Firebase CLI (`npm i -g firebase-tools`).

```powershell
git clone https://github.com/cherotwokibet/realtor-platform.git
cd realtor-platform
dart pub global activate melos
flutter pub get                                   # resolves the whole workspace

cd tools\tenant-cli; npm ci; cd ..\..
node tools\tenant-cli\src\cli.ts validate         # check tenant files
node tools\tenant-cli\src\cli.ts prepare realtime-estates

cd apps\realtor_app
flutter create . --platforms=android,ios,web --org ke.co.realtimeestates --project-name realtor_app
dart run flutter_launcher_icons            # icons from the tenant (config written by prepare)
dart run flutter_native_splash:create      # splash from the tenant
flutter run -d chrome
```

`prepare` generates the realtor's icons, splash, favicons, PWA and share images from the SVGs in `brand/<id>/` (output in `brand/<id>/generated/`, not committed) and writes `flutter_launcher_icons.yaml` / `flutter_native_splash.yaml` for that realtor. The platform folders (`android/`, `ios/`, `web/`) are generated and never committed; tenant-cli writes the tenant-specific parts into them.

Swap to the dummy tenant to see the clone: `node tools\tenant-cli\src\cli.ts prepare demo-homes`, then hot-restart.

### Android flavors (several realtors on one phone)

```powershell
cd apps\realtor_app
flutter create . --platforms=android --project-name realtor_app
node ..\..\tools\tenant-cli\src\cli.ts flavors         # every tenant; or: flavors realtime-estates
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create --flavors demoHomes,realtimeEstates
flutter run --flavor demoHomes
```

Each tenant becomes a flavor (`realtime-estates` → `realtimeEstates`) with its own application ID, launcher name, icon and splash. Its tenant file, logos and fonts go to `assets/flavors/<flavor>/` and are bundled only into that flavor; the app picks the folder from `appFlavor`. `flavors` also empties `assets/tenant/` so no other realtor's files leak into a flavor build (run `prepare <id>` again for web). It rewrites a marked block in `pubspec.yaml`: don't commit that block (a tenant-cli test fails if you do). iOS schemes and per-flavor `firebase_options` come once the Firebase projects exist.

## Web

`flutter build web --release --wasm` builds the app for Firebase Hosting (`firebase.json` → `hosting`: path URLs with an SPA rewrite, and cache headers). The app uses path URLs (`/listing/<slug>`, no `#/`). On screens 840 px and wider, it switches from the bottom bar to a side rail and caps content at 1200 px. After `flutter create`, the icon and splash tools, run `node tools/tenant-cli/src/cli.ts web <id>`. It writes the tenant's title, description, theme colour and Open Graph tags into `web/index.html` and `manifest.json`.

## Feature flags

`features` in the tenant file switches parts of the product on or off. In code, every feature-specific widget sits inside `FeatureGate(feature: Feature.x, ...)` (packages/ui), and every top-level section is an `AppSection` in `apps/realtor_app/lib/src/sections.dart`. A section whose feature is off has no route or menu entry, and deep links to it go home. To add a feature, add the key to the schema, `Feature` and `Features` in packages/core, then gate its UI. Tests in `apps/realtor_app/test/feature_flags_test.dart` switch each one off and check it disappears.

## Tests

```powershell
cd packages\core;   dart test
cd packages\tokens; dart test
cd packages\ui;     flutter test
cd functions;       npm ci; npm test
cd tools\tenant-cli; npm test
```

CI runs all of these on every push, checks that the Dart and TypeScript CSS output match, and builds the web app for both tenants.

## Adding a realtor

See the onboarding steps in the tracker's White-label kit tab. In short: `node tools/tenant-cli/src/cli.ts create <id> "<Name Ltd>"` scaffolds a valid `tenants/<id>.json` and placeholder `brand/<id>/` art; replace the TBC / example.com values and the art, run `validate`, provision the Firebase projects with `infra/terraform` (see its README), then prepare and build.

## Brand assets

Each realtor supplies seven SVGs in `brand/<id>/` (stacked, horizontal and mark, each in light and reverse versions, plus a favicon); see `brand/realtime-estates/BRAND.md`. `node tools/tenant-cli/src/cli.ts icons <id>` builds every raster size the stores and browsers need. Tests check sizes, opacity and the Android safe zone.

## Not yet done

Fonts are named in the tenant file but not bundled yet. The app falls back to the platform font (Roboto on web, fetched from Google) until P1 bundles Poppins/Inter/Manrope per tenant.
