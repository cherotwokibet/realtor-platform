# Security review (P8-s01)

A running record of what was checked, what was found and what is still open. Review again before stage and before prod.

## 28 Oct 2026: rules, callables, dependencies

### Checked and holding
- **No client writes** except a signed-in user's own `savedSearches`. Every other collection is `write: false`; Functions write with the Admin SDK (D7).
- **Personal data** (`leads`, `viewings`, `payments`) is staff-only; agents read only rows with their own `agentId`, and a list query must filter on it (tested).
- **Staff roles** are custom claims set only by `setStaffRole` (owner only, no self-demotion) or the one-time `staff:owner` script. `staff/` and `audit/` are manager-read, never client-written.
- **Audit log** holds ids, states and a label (listing title, staff email); never a client's name or phone.
- **Public listings** are readable only when `status == 'live'`. A rejection note (`rejection.reason`, reviewer uid) cannot reach a live listing: a rejected listing becomes a draft, and the only way on is `submitListing`, which replaces the whole document (emulator test guards this).
- **Storage**: raw uploads are create-only into the uploader's own folder (images under 20 MB); nobody reads `uploads/`; `media/` and `brand/` are public read, never client-written. The media pipeline decodes every upload with sharp, so a forged content type does not get through.
- **Secrets**: none in the repo or Terraform state. Firebase web config is read from Hosting at runtime (D14); the Typesense key is a Secret Manager secret; Google sign-in's client secret was made in the Firebase console, not Terraform.
- **Dependencies**: `npm audit` 0 in `functions` and `tools/tenant-cli` (#43: firebase-admin 14.5, firebase-functions 7.4, grpc-js pinned, sharp 0.35.5).

### Fixed in this review
- **Saved searches accepted any shape.** `filters` was any map and `channels` any list of up to 3 values, so a signed-in user could store junk the saved-search sweep would read. The rules now allow only the schema's filter keys (`purpose` from the known list, `types` ≤ 12, `areas` ≤ 20, integer `minBeds` 0–20 and `maxPriceKES`) and channels from `push` / `email` / `whatsapp`.

### Open
| # | Finding | Risk | Plan |
|---|---|---|---|
| 1 | Public callables (`createLead`, `logContactTap`, `bookViewing`) have no App Check and no rate limit | Spam leads / inflated tap counts; cost | P6 fraud controls: App Check on web and app, per-IP and per-phone limits in the Functions |
| 2 | Lead personal data is kept past `retainUntil` until the scheduled delete exists | DPA 2019 retention | P6 data protection: scheduled Function deletes expired leads (D12) |
| 3 | No load test yet on search and listing pages | Unknown capacity | k6 against dev share pages once deployed |
| 4 | No pen-test checklist run | — | Before prod: OWASP ASVS L1 pass over admin, share pages and callables |
