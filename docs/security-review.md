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

- **No security headers anywhere.** Share pages now send a CSP (`default-src 'none'`, inline styles, `https:` images, same-origin forms, no framing), nosniff, `X-Frame-Options`, Referrer-Policy and Permissions-Policy on every response. The admin Hosting site sends nosniff, `DENY` framing and Referrer-Policy. The app's default site sends nosniff and Referrer-Policy (no framing headers: it serves the Auth iframe the admin embeds).

### Open
| # | Finding | Risk | Plan |
|---|---|---|---|
| 1 | Public callables (`createLead`, `logContactTap`, `bookViewing`) have no App Check. Rate limits are in (P6-s05): per hour, 5 enquiries per phone or email and 30 per listing, 3 viewings per phone and 20 per listing, 300 taps per listing | Spam leads (now bounded) | P6-s05: App Check on the app and web (reCAPTCHA Enterprise key in Terraform, then enforce once clients send tokens) |
| 2 | Lead personal data is kept past `retainUntil` until the scheduled delete exists | DPA 2019 retention | P6 data protection: scheduled Function deletes expired leads (D12) |
| 3 | Load test scripts ready (`tools/load/`, CI smoke green); no run against a deployed environment yet | Unknown capacity | Boniface runs `PROFILE=load` against dev share pages once deployed, and search once the Typesense host exists (D4); record p95 and errors here |
| 4 | ASVS L1 pass done (`docs/asvs-l1.md`): no critical findings. Open from it: server-side password policy (console, Boniface), full CSP on the Flutter sites and alerting | Low | Re-run before stage and prod; CSP report-only on dev first; alerts in P8-s02 (Dependabot is on) |
