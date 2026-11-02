# Data model v2

Approved by Boniface on 24 Oct 2026.

One Firestore database per tenant project (D1), so documents carry no tenant id. Schemas live in `functions/src/model/schema.ts` (zod). Functions validate every write against them, and the emulator seed (`functions/src/seed/`) must pass them too.

**Who writes:** clients read public data and create only what a visitor can create (a lead, a viewing request). Every field marked *Functions* is set only by Cloud Functions with the Admin SDK (D7). `firestore.rules` enforces this, and `functions/src/rules/firestore.rules-test.ts` tests every collection in the emulator (`npm --prefix functions run test:rules` inside `firebase emulators:exec`). Staff roles are custom claims (`role`: owner / manager / agent, plus `agentId` for agents) set by the owner-only `setStaffRole` Function; the first owner of a project comes from `npm --prefix functions run staff:owner` (once). Agents read only their own leads, viewings and draft listings. The only client write is a signed-in user's own saved searches, and even then only `filters` and `channels` can change.

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
| ″ | status (draft → pending → live → expired / let / sold, moves in `listing-rules.ts`), verifiedAt, expiresAt, featuredUntil, stats {views, leads, calls, whatsapps}, createdAt, updatedAt | *Functions* |
| `agents/{id}` | name, photo, earbNo, phone, whatsapp, languages (en / sw), rating, responseMins, active | Admin via Functions; rating and responseMins *Functions* (responseMins: nightly `agentResponseTimes`, the median first reply over 90 days, null under 3 replies) |
| `leads/{id}` | listingId, agentId, channel (call / whatsapp / form / viewing), contact {name, phone, email}, message, stage (new → … → won / lost), **consentAt**, **retainUntil**, createdAt; firstResponseAt + responseMins (set by the first move out of new, P5-s03) | Created by `createLead`; stage moves by agents via Functions |
| `viewings/{id}` | listingId, agentId, slot, client {name, phone}, status (requested / confirmed / done / no-show / cancelled), feeKES, paymentId, createdAt | Requested by clients via `bookViewing`; status *Functions* |
| `payments/{id}` | purpose (viewing-fee / deposit / featured-ad), amountKES, phone, listingId, checkoutRequestId, status (pending / paid / failed / cancelled), receipt | *Functions only* (Daraja, P6) |
| `savedSearches/{id}` | userId, filters {purpose, types, areas, minBeds, maxPriceKES}, channels (push / email / whatsapp), lastNotifiedAt | The signed-in user; lastNotifiedAt *Functions* |
| `staff/{uid}` | email, name, role (owner / manager / agent), agentId, updatedAt | *Functions only* (`setStaffRole`, mirror of the custom claims); managers read all, staff read their own |
| `audit/{id}` | at, actor {uid, role, agentId}, action (lead.stage / listing.submit / listing.approve / …), target {collection, id, label}, from, to, reason | *Functions only*, in the same transaction as the change; owners and managers read. Ids, states and a label (listing title, staff email); no client personal data |
| `areas/{slug}` | name, county, centre (geo), guide, amenities[], stats {medianRentKES, listings} | Admin; stats *Functions* |
| `rateLimits/{sha256}` | window, count, expiresAt (one-hour windows per contact and per listing, P6-s05; no contact details, id is a hash; Firestore TTL deletes it) | *Functions only*; no client access |
| `photoHashes/{band}_{hex}` | entries[] {h: dHash, l: listingId, m: mediaId}: the 8×8-bit band index of every listing photo's dHash (P6-s05) | *Functions only*; no client access |
| `photoFlags/{listingId}_{mediaId}` | listingId, mediaId, matches[] {listingId, mediaId, bits}, at: a photo within 6 bits of another listing's | *Functions only*; managers read (admin Listings shows a flag) |
| `stats/recommendations-YYYY-MM-DD` | day, app {shown, opened}, web {shown, opened}: per Nairobi day, how often "Similar homes" was shown under a listing and a home opened from it (P7-s04). Counts only | *Functions only* (`logRecommendation`); no client access; the monthly report adds them up |
| `config/tenant` | Read-only copy of the tenant file for runtime flags | Deploy step |

**Data Protection Act 2019:** every lead records when consent was given (`consentAt`) and when the record is to be deleted (`retainUntil`, after `consentAt`). A lead needs a phone or an email. The scheduled `purgeExpiredLeads` Function (03:15 Nairobi time, nightly) deletes leads past `retainUntil`, and viewings whose slot is 24 months old (a viewing's client details come with the same consent as its lead). It logs only counts. Export and delete requests go through `dataRequest` (the admin's *Privacy* page). `createLead` stores emails lowercased so one address finds all its leads.

## Callable API (P2-s03)

Inputs are validated with zod in `functions/src/api/`, and the stored document is checked against the collection schema before it is written.

| Callable | Who | What it does |
|---|---|---|
| `createLead` | anyone, with the consent tick | Lead on a **live** listing, assigned to that listing's agent; sets `consentAt` and `retainUntil` (24 months, D12) and adds 1 to the listing's `stats.leads` |
| `logContactTap` | anyone | Adds 1 to a **live** listing's `stats.calls` or `stats.whatsapps` (D13). Stores no personal data and no lead. Counter-only writes do not re-sync search |
| `logRecommendation` | anyone | P7-s04: adds 1 to today's `shown` or `opened` for the app or web in `stats/recommendations-<day>`; rate-limited per listing, App Check watched, share-pages twin `shareLogRecommendation`. No personal data |
| `bookViewing` | anyone, with the consent tick | Requests a viewing of a **live** listing with its agent: a half-hour slot, Mon–Sat, 08:00–17:30 Nairobi time, at least 2 hours and at most 30 days ahead. One active booking per agent per slot (id `<agentId>_<slot ms>`; a cancelled slot frees up). The client's name and phone are also stored as a lead (channel `viewing`, consent and 24-month retention) and counted in `stats.leads`. Fee is 0 until M-Pesa (P6) |
| `updateViewingStatus` | the viewing's agent, or a manager | P5-s05: requested → confirmed / cancelled; confirmed → done / no-show (only after the time) / cancelled (`transitions.json` `viewingStatus`, mirrored in the admin). A cancelled slot can be booked again. Audited `viewing.status`, labelled by listing and time, never the client. Admin: *Viewings* (open ones from 14 days back, earliest first; history by status) |
| `updateLeadStage` | the lead's agent, or a manager | new → contacted → viewing → offer → won, any stage → lost, and lost → contacted |
| `submitListing` | agents (as themselves), managers (for any agent) | Create or edit → `pending`; sets slug (unique), geohash, stats and timestamps; the area must exist. `media` may only reorder or drop the listing's own pipeline-made entries (the stored copies are kept); left out, the media stay as they are |
| `moderateListing` | managers | approve (live, verified for 30 days), reject (needs a reason), expire, let, sold; status moves from `listing-rules.ts` |
| `confirmListing` | the listing's agent, or a manager | P6-s02: a live or expired listing is still available → live, `verifiedAt` now, `expiresAt` +30 days; audited `listing.confirm`. The nightly `expireListings` job moves live listings past `expiresAt` to expired (audited as *Nightly expiry*) |
| `featureListing` | managers | P5-s02: a live listing ranks first in search for `days` (≤ 90); 0 stops it; audited `listing.feature`. The nightly job clears lapsed `featuredUntil` so search re-syncs |
| `importListings` | managers | P5-s02 CSV import: up to 100 rows per call, each a new listing submitted exactly as `submitListing` (pending, audited) for the agent it names; bad rows are reported by row, the rest go in. The admin's *Import CSV…* parses and checks the sheet first (`ListingCsv` in packages/core) |
| `dataRequest` | owners and managers | DPA 2019 subject request: finds a person's leads and viewings by phone or email and returns them as JSON (`export`) or deletes them (`delete`); audited as `privacy.export` / `privacy.delete` with counts only. Admin: *Privacy* |

Still to come: rate limits on the public callables (P6 fraud controls), confirming and cancelling viewings from admin (P5 bookings), and agent availability instead of fixed hours.

## Media pipeline (P2-s04, D6)

Agents upload raw photos to `uploads/agents/<agentId>/listings/<listingId>/` (managers to `uploads/staff/<uid>/listings/<listingId>/`). `storage.rules` allows images under 20 MB into your own folder only. The `onListingPhoto` trigger then:

- checks the listing exists and belongs to that agent
- rejects photos under 1024 px on the long edge, recording `lastMediaError` on the listing
- applies EXIF rotation and drops all metadata (GPS)
- writes WebP variants `thumb` 320, `card` 800 and `full` 1600, with the tenant mark (`brand/watermark.png`, if present) on card and full
- adds `{kind: 'photo', variants, blurhash, width, height}` to `media`
- deletes the raw upload

Variants under `media/` are public and cached for a year. Videos become an HLS ladder (720p/360p) and a poster under `media/listings/<id>/<mediaId>/`, made by the Cloud Run job `transcode-video` (D15).

## Search (P2-s05, D4)

Live listings are mirrored into a Typesense collection named `<TENANT_ID>_listings` by the `search-onListingWrite` trigger. Anything that stops being live (pending, expired, let, sold, deleted) is removed. The search document carries the facet fields (type, beds, area, amenities, verified, priceKES), a geopoint, `featured`, and the thumb and blurhash of the first photo.

`functions/src/search/schema.ts` → `toSearchParams()` turns the shared filter model into a Typesense query: purpose, types, areas, minimum beds, price range, amenities, verified only, radius around a point, sort (newest with featured first, price ascending or descending, nearest) and paging. The share-page URLs and app deep links use the same model. Values are quoted so user input can't widen a filter.

Search is off for a project until it is set up, and then the trigger deploys with the rest: `TENANT_ID` and `TYPESENSE_HOST` in `functions/.env.<project-id>` (local, not committed) and the `TYPESENSE_API_KEY` secret in Secret Manager. Without them a deploy skips the trigger and asks for nothing (`functions/src/search/config.ts`). CI runs the integration test against a Typesense container: facets, filters, a 2 km radius, typo tolerance, and under 100 ms.

## Indexes

`firestore.indexes.json` covers the first queries: live listings in an area by price, all listings in an area by price, and an agent's leads newest first. Search with facets moves to Typesense (P2-s05, D4).

## Running the seed

```sh
firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run seed"
```

The script refuses to run without `FIRESTORE_EMULATOR_HOST`, so it can never write to a real project. It loads 8 Nairobi-area areas, 3 fictional agents, 12 listings and a lead, then reads the counts back and runs an area query. CI runs the same command.
