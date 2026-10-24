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
tools/tenant-cli     validate / css / prepare (create, deploy, build later)
infra/terraform      per-tenant Firebase + Typesense            (P1)
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

`prepare` generates the realtor's icons, splash, favicons, PWA and share images from the SVGs in `brand/<id>/` (output in `brand/<id>/generated/`, not committed) and writes `flutter_launcher_icons.yaml` / `flutter_native_splash.yaml` for that realtor. The platform folders (`android/`, `ios/`, `web/`) are generated per tenant and not committed until P1 "Flutter flavors generator" makes them tenant-neutral.

Swap to the dummy tenant to see the clone: `node tools\tenant-cli\src\cli.ts prepare demo-homes`, then hot-restart.

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

See the onboarding steps in the tracker's White-label kit tab. In short: add `tenants/<id>.json` and `brand/<id>/`, run `validate`, provision the Firebase projects, prepare and build.

## Brand assets

Each realtor supplies seven SVGs in `brand/<id>/` (stacked, horizontal and mark, each in light and reverse versions, plus a favicon); see `brand/realtime-estates/BRAND.md`. `node tools/tenant-cli/src/cli.ts icons <id>` builds every raster size the stores and browsers need. Tests check sizes, opacity and the Android safe zone.

## Not yet done

Fonts are named in the tenant file but not bundled yet. The app falls back to the platform font (Roboto on web, fetched from Google) until P1 bundles Poppins/Inter/Manrope per tenant.
