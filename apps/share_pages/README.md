# Share pages (D2, P3-s03)

A small Dart server that renders plain HTML for Google and WhatsApp, built with Jaspr's server rendering (`renderComponent`) behind a shelf router. It runs on Cloud Run behind Firebase Hosting rewrites. Visitors are handed to the Flutter app at `app.<domain>` on the same path.

Live now:

- `/listing/<slug>`: title, price with its period, facts, up to 6 lazy photos (media-pipeline `card` variants) and amenities
- **Open in app** and **Ask on WhatsApp** buttons (the WhatsApp button appears only when the tenant has a number)
- `<link rel="canonical">`, Open Graph and Twitter tags (`og:image` is the first `full` photo, else `https://app.<domain>/og.png`)
- JSON-LD `RealEstateListing` with an `Offer` in KES, `Accommodation` facts and geo
- Styles are the tenant's CSS variables (`packages/tokens`) plus layout-only CSS, so a re-brand needs no code change
- `Cache-Control: public, max-age=300, s-maxage=600`
- Unknown slugs get a small HTML 404
- `/area/<slug>`: the area guide, typical rent, live homes (newest first, linking to their pages) and a button into the app search (`/rent/<area>`); JSON-LD `Place` with an `ItemList` of the listings
- `/agent/<id>`: an active agent's name, photo, EARB number, languages, typical reply time, **Chat on WhatsApp** and **Call** buttons, and their live homes; JSON-LD `RealEstateAgent` under the realtor. Inactive or unknown agents are 404s. Listing pages say "Listed by <agent>" with a link.
- `/`: the realtor's 12 newest live homes and every area, with **Search homes** into the app and the realtor's WhatsApp
- **Lead capture (P3-s06):**
  - Listing pages carry an **Ask about this home** form: phone (any Kenyan mobile format, normalised to +254), optional name and message, a consent tick quoting the 24-month retention (D12), and a hidden honeypot field.
  - The form posts to `/listing/<slug>/enquire`, which checks it, calls the `createLead` Function and redirects back with a thank-you (`?sent=1`). Errors re-show the form with what was typed.
  - Pages showing a visitor's own input are `private, no-store`, so the CDN never keeps them.
  - **Ask on WhatsApp** goes through `/go/whatsapp/<slug>`, which calls `logContactTap` (a counter, no personal data, D13) and redirects to `wa.me`. A failed count never blocks WhatsApp. `/go/` is disallowed in robots.txt.
  - The server never writes Firestore and never logs form contents; Functions do the storing (D7). `FUNCTIONS_BASE` overrides the default `https://europe-west1-<project>.cloudfunctions.net`.
- **App Links / Universal Links (P3-s07):** `/.well-known/assetlinks.json` and `/.well-known/apple-app-site-association` let the installed app open `/listing/`, `/area/` and `/agent/` links. They are built from `apps.androidCertSha256` and `apps.appleTeamId` in the tenant file. Until those exist, both files are valid but claim nothing. `tenant flavors` adds the matching `autoVerify` intent filter for each flavor's share domain to the Android manifest, and CI checks it in every APK. `tenant web` rewrites old `#/…` links to paths before Flutter starts.
- `/sitemap.xml` (home, every area, every active agent, every live listing with `lastmod`) and `/robots.txt` pointing at it

Listing text is HTML-escaped by Jaspr. Inside the JSON-LD script, every `<` is written as `\u003c`, so a title can't close the script. A test covers this.

Listings come from Firestore over REST (`FirestoreListingSource`): a `runQuery` for `slug == <slug> AND status == live`. On Cloud Run the token comes from the metadata server (the service account needs Firestore read). Against the emulator, set `FIRESTORE_EMULATOR_HOST`. `FIRESTORE_PROJECT` overrides the tenant's prod project.

```sh
cd apps/share_pages
dart test -x emulator                       # unit tests
# against the seeded emulator (CI does this):
firebase emulators:exec --only firestore --project demo-realtor \
  "npm --prefix functions run seed && cd apps/share_pages && dart test -t emulator"
mkdir -p build && dart compile exe bin/server.dart -o build/server
TENANT_FILE=../../tenants/demo-homes.json PORT=8080 ./build/server
```

## Cloud Run

`apps/share_pages/Dockerfile` builds one image per tenant from the repo root. It resolves only `core`, `tokens` and `share_pages` (`docker/workspace.pubspec.yaml`, named so the analyzer does not treat it as a package), because the repo workspace also lists Flutter packages. The final image is `scratch` plus the Dart runtime files, the AOT binary and `tenants/<id>.json`, and it runs as a non-root user. CI builds it for `demo-homes` and smoke-tests `/healthz` and `/robots.txt`.

```sh
docker build -f apps/share_pages/Dockerfile --build-arg TENANT=<id> -t share-pages .
```

Terraform (`infra/terraform/modules/firebase-env`) creates a `share-pages` service account with `roles/datastore.viewer` only, and, once `share_pages_image` is set, a Cloud Run service (scale 0 to 3, 1 CPU, 256 MiB, `/healthz` startup probe, `FIRESTORE_PROJECT` set to the environment's project) that `allUsers` may invoke. Pushing the image to Artifact Registry, and the Hosting rewrite from the share domain, happen at deploy time, which Boniface runs.

The home page's "newest first" query needs the `(status, updatedAt desc)` index in `firestore.indexes.json`. Every other query is equality-only, sorted in Dart.
