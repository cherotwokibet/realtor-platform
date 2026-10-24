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
- `/sitemap.xml` (home, every area, every live listing with `lastmod`) and `/robots.txt` pointing at it

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

Next: agent and home pages.
