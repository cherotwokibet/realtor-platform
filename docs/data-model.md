# Data model v2

Approved by Boniface on 24 Oct 2026.

One Firestore database per tenant project (D1), so documents carry no tenant id. Schemas live in `functions/src/model/schema.ts` (zod). Functions validate every write against them, and the emulator seed (`functions/src/seed/`) must pass them too.

**Who writes:** clients read public data and create only what a visitor can create (a lead, a viewing request). Every field marked *Functions* is set only by Cloud Functions with the Admin SDK (D7). The security rules that enforce this are P2 "Security rules + tests"; until then the rules deny everything.

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

## Indexes

`firestore.indexes.json` covers the first queries: live listings in an area by price, all listings in an area by price, and an agent's leads newest first. Search with facets moves to Typesense (P2-s05, D4).

## Running the seed

```sh
firebase emulators:exec --only firestore --project demo-realtor "npm --prefix functions run seed"
```

The script refuses to run without `FIRESTORE_EMULATOR_HOST`, so it can never write to a real project. It loads 8 Nairobi-area areas, 3 fictional agents, 12 listings and a lead, then reads the counts back and runs an area query. CI runs the same command.
