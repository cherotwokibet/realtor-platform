# OWASP ASVS 5.0 Level 1: checklist (P8-s01)

A pass over the four surfaces that face the internet: the **admin** (Flutter web on Hosting), the **app** (Flutter web and mobile), the **share pages** (Cloud Run behind Hosting) and the **callable Functions**. Firebase Auth, Firestore and Storage are Google's. What we own is their configuration and our rules.

Status: ✅ holds · ⚠️ gap, with plan · ➖ not applicable. Grouped by ASVS 5.0 chapter. Re-run this before stage and again before prod, and record the result in `docs/security-review.md`.

## V1 Encoding and sanitization
- ✅ Share pages: all text goes through Jaspr's HTML escaping. Inside JSON-LD, `<` is written as `<` (test: *user text is escaped*).
- ✅ Flutter renders text with no HTML, and no `HtmlElementView` takes user input.
- ✅ No raw query strings. Firestore is queried with typed filters, and Typesense filters come from `toSearchParams` over typed `ListingFilters`.

## V2 Validation and business logic
- ✅ Every callable parses its input with zod and rejects unknown shapes (`functions/src/api/*`).
- ✅ Money, approval, verification and commission logic is in Functions only (D7). Clients only read, except their own `savedSearches`, whose shape the rules now pin.
- ✅ State changes follow `functions/src/model/transitions.json`. An invalid move is a `failed-precondition`.
- ✅ Public callables are rate-limited per contact and per listing, inside the same transaction, so a refused call writes nothing (`functions/src/api/ratelimit.ts`). The share pages form has a honeypot and answers a limit with 429 and a plain message. Limits are not per IP: the share pages call from one server address.
- ⚠️ No App Check yet. **Plan:** D16 (Proposed): App Check on the app and web, and service-account-only twins for the share pages server, then enforce.

## V3 Web frontend security
- ✅ Share pages send CSP `default-src 'none'` with only inline styles, `https:` images and same-origin form posts. They also send `frame-ancestors 'none'`, nosniff, `X-Frame-Options: DENY`, a strict Referrer-Policy and a closed Permissions-Policy (test: *every response carries the security headers*).
- ✅ Admin: nosniff, `X-Frame-Options: DENY`, `frame-ancestors 'none'`, Referrer-Policy, `noindex` (`firebase.json`).
- ✅ App: nosniff and Referrer-Policy. It has no framing headers, because the default site also serves Firebase Auth's `/__/auth/` iframe, which the admin embeds.
- ⚠️ No full CSP on the Flutter sites. CanvasKit, wasm and the Auth popup need a hand-tuned policy. **Plan:** try one in report-only mode on dev before prod.
- ✅ HTTPS only. Hosting and Cloud Run serve TLS, and Hosting sends HSTS.

## V4 API and web service
- ✅ Callables are POST-only (Firebase protocol), and errors return a code and message, never a stack.
- ✅ The share pages only GET from Firestore over REST with a read-only service account (`roles/datastore.viewer`). Form posts go to Functions, never to Firestore.

## V5 File handling
- ✅ Uploads are create-only into the uploader's own `uploads/<uid>/` folder, images only, under 20 MB. Nobody reads `uploads/`.
- ✅ Every upload is decoded and re-encoded by sharp (`onListingPhoto`). Only the generated variants are public.

## V6 Authentication
- ✅ Firebase Auth: email and password plus Google (D14). Passwords are hashed by Google, sign-in is throttled (`too-many-requests`), and reset goes by email link.
- ✅ The admin asks for at least 8 characters when creating an account.
- ⚠️ The server-side minimum is still Firebase's default of 6. A direct REST sign-up could set a shorter password. That account would have no role, but the minimum should hold on the server. **Boniface:** Firebase console → Authentication → Settings → Password policy → *Require enforcement*, minimum length 8 (dev, stage and prod). Terraform's provider has no setting for this yet.
- ➖ MFA is Level 2. Consider it for owners before prod.

## V7 Session management
- ✅ Sessions are Firebase ID tokens (1-hour life), refreshed by the SDK. Sign-out clears them on the device.
- ⚠️ Removing someone's staff role takes effect at their next token refresh, which is at most 1 hour later. **Plan:** accept this for L1. To cut access immediately, the owner can also disable the account (Authentication → Users). Revisit with `revokeRefreshTokens` if staff churn makes it matter.

## V8 Authorization
- ✅ Roles are custom claims, set only by `setStaffRole` (owner only) or the one-time `staff:owner` script. The rules and Functions check them on every read and call.
- ✅ Agents see only rows with their own `agentId`, and list queries must filter on it (rules tests).
- ✅ Every privileged change writes `audit/` with actor, target, from and to.

## V9 Self-contained tokens
- ✅ ID tokens are verified by Firebase (signature, audience, expiry). We never mint or parse JWTs ourselves.

## V10 OAuth and OIDC
- ✅ Google sign-in goes through Firebase's popup flow. Its client secret lives only in Firebase (made in the console, never in Terraform state). Authorized domains are listed in Terraform.

## V11 Cryptography
- ✅ No custom cryptography. TLS, hashing and token signing are Google's.

## V12 Secure communication
- ✅ TLS everywhere. Functions call Typesense over HTTPS on 443 only (`functions/src/index.ts`).

## V13 Configuration
- ✅ No secrets in the repo or state. Values are `secret://` references to Secret Manager (D7), and GitGuardian runs on every PR.
- ✅ `npm audit` is at 0 for `functions` and `tools/tenant-cli`.
- ✅ Dependabot opens weekly grouped PRs for npm, pub, Actions and the share pages base image (`.github/dependabot.yml`).

## V14 Data protection
- ✅ Personal data (`leads`, `viewings`, `payments`) is staff-only. The audit log holds no names or phones, and the share pages never log form contents.
- ✅ Personal pages (a visitor's own form input) are `private, no-store`.
- ✅ Leads past `retainUntil`, and viewings 24 months after their slot, are deleted nightly by `purgeExpiredLeads` (D12, DPA 2019).

## V15 Secure coding and architecture
- ✅ Each tenant gets its own Firebase project (D1), so one realtor's data and keys never share a database with another's.

## V16 Logging and error handling
- ✅ Errors are logged by status or type only, never with request bodies (share pages, Functions).
- ⚠️ No alerting yet. **Plan:** P8-s02.

## V17 WebRTC
- ➖ Not used.

## Summary
There are no critical findings. These gaps are open, each with an owner:
1. App Check (P6-s05)
2. Server-side password policy (Boniface, console)
3. Full CSP on the Flutter sites (before prod)
4. Alerting (P8-s02)
