# Decisions

The live list is the Decisions tab of the build tracker (pinned in the Realtor Platform Claude Project). Summary:

| ID | Decision | Status |
|----|----------|--------|
| D1 | One Firebase project per realtor (dev/stage/prod), one shared monorepo | Proposed |
| D2 | Flutter for app (Android/iOS/web) + admin; Jaspr share pages for SEO | Decided 8 Oct 2026 |
| D3 | Admin rebuilt in Flutter web on the new data layer | Decided 8 Oct 2026 |
| D4 | Typesense for search | Proposed |
| D5 | Riverpod + go_router; no GetX | Decided 8 Oct 2026 |
| D6 | Firebase-native media pipeline (Storage trigger → sharp/ffmpeg) | Decided |
| D7 | Money, approval, verification, commission logic server-side only | Proposed |
| D8 | Rebuild from scratch in repos and Firebase projects owned by Boniface; vendor code is reference | Decided 15 Oct 2026 |
| D9 | Tenant tooling in TypeScript on Node 22 (runs in CI without Flutter); Dart and TS CSS output must match | Proposed 24 Oct 2026 |
| D10 | Brand: roofline concept is the primary logo (traced to vector, black → maroon #5E0202, gold kept); sunset concept is marketing-only; icons generated from tenant SVGs | Decided 24 Oct 2026 |
| D11 | Fonts bundled in-repo as static, Latin-subset TTFs (`fonts/`), copied per tenant by `prepare` and registered at runtime with `FontLoader`; no `google_fonts` package or runtime download | Decided 24 Oct 2026 |
| D12 | Lead personal data kept 24 months from consent (`retainUntil`), then deleted by a scheduled Function (P6) | Decided 24 Oct 2026 |
| D13 | A call or WhatsApp tap carries no contact details, so it is counted on the listing (`stats.calls`, `stats.whatsapps`) and not stored as a lead. Leads come only from forms with the consent tick and a phone or email (enquiries now, viewing requests later). Reversible: taps can become leads once a signed-in user's phone is known | Decided 25 Oct 2026 |
| D14 | Staff sign in to the admin with email + password or Google (Firebase Auth; passwords never pass through our code or repo). Roles are custom claims set only by the owner-only `setStaffRole` Function, the first owner by a one-time script. The admin is a separate Firebase web app on its own Hosting site and reads its Firebase config from Hosting's `/__/firebase/init.json` at runtime, so no config is committed; anywhere else it runs on demo data | Decided 27 Oct 2026 |
| D16 | App Check guards the public callables (`createLead`, `bookViewing`, `logContactTap`): reCAPTCHA Enterprise on the Flutter web app, Play Integrity on Android, App Attest on iOS, keys made in Terraform. The share pages call from their own server, where App Check cannot attest, so they get internal HTTPS twins of the three Functions that only the `share-pages` service account may invoke (Cloud Run IAM, OIDC token from the metadata server); same validation, rate limits and transaction code. Rollout: register and watch App Check metrics on dev first, enforce once real traffic shows tokens. Reversible: enforcement is one flag per Function | Proposed 28 Oct 2026 |
