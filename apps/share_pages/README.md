# Share pages (D2, P3-s03)

A small Dart server that renders plain HTML for Google and WhatsApp, built with Jaspr's server rendering (`renderComponent`) behind a shelf router. It runs on Cloud Run behind Firebase Hosting rewrites. Visitors are handed to the Flutter app at `app.<domain>` on the same path.

Live now:

- `/area/<slug>`: the area guide, typical rent, live homes (newest first, linking to their pages) and a button into the app search (`/rent/<area>`); JSON-LD `Place` with an `ItemList` of the listings
- `/sitemap.xml` (home, every area, every live listing with `lastmod`) and `/robots.txt` pointing at it

- `/listing/<slug>`: title, price with its period, facts, up to 6 lazy photos (media-pipeline `card` variants) and amenities
- **Open in app** and **Ask on WhatsApp** buttons (the WhatsApp button appears only when the tenant has a number)
- `<link rel="canonical">`, Open Graph and Twitter tags (`og:image` is the first `full` photo, else `https://app.<domain>/og.png`)
- JSON-LD `RealEstateListing` with an `Offer` in KES, `Accommodation` facts and geo
- Styles are the tenant's CSS variables (`packages/tokens`) plus layout-only CSS, so a re-brand needs no code change
- `Cache-Control: public, max-age=300, s-maxage=600`
- Unknown slugs get a small HTML 404

Listing text is HTML-escaped by Jaspr. Inside the JSON-LD script, every `<` is written as `<`, so a title can't close the script. A test covers this.

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

Next: agent and home pages, and the Cloud Run deploy.
