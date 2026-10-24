# Data model v2

Approved by Boniface on 24 Oct 2026.

One Firestore database per tenant project (D1), so documents carry no tenant id. Schemas live in `functions/src/model/schema.ts` (zod). Functions validate every write against them, and the emulator seed (`functions/src/seed/`) must pass them too.

**Who writes:** clients read public data and create only what a visitor can create (a lead, a viewing request). Every field marked *Functions* is set only by Cloud Functions with the Admin SDK (D7). `firestore.rules` enforces this, and `functions/src/rules/firestore.rules-test.ts` tests every collection in the emulator (`npm --prefix functions run test:rules` inside `firebase emulators:exec`). Staff roles are custom claims (`role`: owner / manager / agent, plus `agentId` for agents) set by a Function. Agents read only their own leads, viewings and draft listings. The only client write is a signed-in user's own saved searches, and even then only `filters` and `channels` can change.

## Conventions

- Money is integer shillings in fields ending `KES` (`priceKES`, `feeKES`), from 0 to 10 billion. Never decimals.
- Phones are E.164 Kenyan mobiles: `+2547…` or `+2541…`.
- Times are Firestore Timestamps (`Date` in the schemas).
- `geo` is `{lat, lng, geohash}` with a 9-character geohash (about 5 m) for radius queries.
- `slug` is lowercase-hyphenated, at most 80 chars, and unique per collection.

## Collections

| Collection | Key fields | Written by |
|---|---|---|
| `listings/{id}` | title, slug, purpose (rent / sale / short-stay), type (bedsitter … commercial), beds, baths, priceKES, depositMonths (required for rent), serviceChargeKES, geo, area (→ areas slug), estate, amenities[], utilities {water, electricity, wifi}, media[] {kind, variants, blurhash}, agentId | Agents propose via Functions (`submitListing`, P2-s03) |
| ″ | status (draft → pending → live → expired / let / sold, moves in `listing-rules.ts`), verifiedAt, expiresAt, featuredUntil, stats {views, leads}, createdAt, updatedAt | *Functions* |
| `agents/{id}` | name, photo, earbNo, phone, whatsapp, languages (en / sw), rating, responseMins, active | Admin via Functions; rating and responseMins *Functions* |
| `leads/{id}` | listingId, agentId, channel (call / whatsapp / form / viewing), contact {name, phone, email}, message, stage (new → … → won / lost), **consentAt**, **retainUntil**, createdAt | Created by `createLead`; stage moves by agents via Functions |
| `viewings/{id}` | listingId, agentId, slot, client {name, phone}, status (requested / confirmed / done / no-show / cancelled), feeKES, paymentId, createdAt | Requested by clients via `bookViewing`; status *Functions* |
| `payments/{id}` | purpose (viewing-fee / deposit / featured-ad), amountKES, phone, listingId, checkoutRequestId, status (pending / paid / failed / cancelled), receipt | *Functions only* (Daraja, P6) |
| `savedSearches/{id}` | userId, filters {purpose, types, areas, minBeds, maxPriceKES}, channels (push / email / whatsapp), lastNotifiedAt | The signed-in user; lastNotifiedAt *Functions* |
| `areas/{slug}` | name, county, centre (geo), guide, amenities[], stats {medianRentKES, listings} | Admin; stats *Functions* |
| `config/tenant` | Read-only copy of the tenant file for runtime flags | Deploy step |

**Data Protection Act 2019:** every lead records when consent was given (`consentAt`) and when the record is to be deleted (`retainUntil`, after `consentAt`). A lead needs a phone or an email. Export and delete requests are P6 "Data protection compliance".

## Callable API (P2-s03)

Inputs are validated with zod in `functions/src/api/`, and the stored document is checked against the collection schema before it is written.

| Callable | Who | What it does |
|---|---|---|
| `createLead` | anyone, with the consent tick | Lead on a **live** listing, assigned to that listing's agent; sets `consentAt` and `retainUntil` (24 months, D12) and adds 1 to the listing's `stats.leads` |
| `updateLeadStage` | the lead's agent, or a manager | new → contacted → viewing → offer → won, any stage → lost, and lost → contacted |
| `submitListing` | agents (as themselves), managers (for any agent) | Create or edit → `pending`; sets slug (unique), geohash, stats and timestamps; the area must exist |
| `moderateListing` | managers | approve (live, verified for 30 days), reject (needs a reason), expire, let, sold; status moves from `listing-rules.ts` |

Still to come in P2-s03: `bookViewing`, plus rate limits on `createLead` (P6 fraud controls).

## Media pipeline (P2-s04, D6)

Agents upload raw photos to `uploads/agents/<agentId>/listings/<listingId>/` (managers to `uploads/staff/<uid>/listings/<listingId>/`). `storage.rules` allows images under 20 MB into your own folder only. The `onListingPhoto` trigger then:

- checks the listing exists and belongs to that agent
- rejects photos under 1024 px on the long edge, recording `lastMediaError` on the listing
- applies EXIF rotation and drops all metadata (GPS)
- writes WebP variants `thumb` 320, `card` 800 and `full` 1600, with the tenant mark (`brand/watermark.png`, if present) on card and full
- adds `{kind: 'photo', variants, blurhash, width, height}` to `media`
- deletes the raw upload

Variants under `media/` are public and cached for a year. Video (ffmpeg → HLS) comes next.

## Search (P2-s05, D4)

Live listings are mirrored into a Typesense collection named `<TENANT_ID>_listings` by the `onListingWrite` trigger. Anything that stops being live (pending, expired, let, sold, deleted) is removed. The search document carries the facet fields (type, beds, area, amenities, verified, priceKES), a geopoint, `featured`, and the thumb and blurhash of the first photo.

`functions/src/search/schema.ts` → `toSearchParams()` turns the shared filter model into a Typesense query: purpose, types, areas, minimum beds, price range, amenities, verified only, radius around a point, sort (newest with featured first, price ascending or descending, nearest) and paging. The share-page URLs and app deep links use the same model. Values are quoted so user input can't widen a filter.

Deploy settings per tenant project: `TENANT_ID` and `TYPESENSE_HOST` (params in `functions/.env.<project>`), and the `TYPESENSE_API_KEY` secret in Secret Manager. CI runs the integration test against a Typesense container: facets, filters, a 2 km radius, typo tolerance, and under 100 ms.

## Indexes

`firestore.indexes.json` covers the first queries: live listings in an area by price, all listings in an area by price, and an agent's leads newest first. Search with facets moves to Typesense (P2-s05, D4).

## Running the seed

```sh
firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run seed"
```

The script refuses to run without `FIRESTORE_EMULATOR_HOST`, so it can never write to a real project. It loads 8 Nairobi-area areas, 3 fictional agents, 12 listings and a lead, then reads the counts back and runs an area query. CI runs the same command.
