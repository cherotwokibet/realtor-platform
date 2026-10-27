# Admin / CRM (Phase 5)

Flutter web app for staff, sharing `packages/core` and `packages/ui` with the customer app. The information architecture comes from the vendor's Miro wireframes (`Real estate LTD.pdf`, 50 frames). The vendor admin code is reference only (D3, D8).

## Roles

Staff roles are custom claims set by a Function (`role`: owner / manager / agent, plus `agentId` for agents). `StaffUser` in `packages/core` reads them and decides what each role opens; `firestore.rules` enforces the same split on the data.

| | Leads | Listings | Audit log |
|---|---|---|---|
| Owner, manager | all | all | yes |
| Agent | own | own | no |

Every table pages on the server (`startAfter` + `limit`), newest first.

Changes go through the Functions, which check the role, apply the change and write the audit log in one transaction (D7): an agent moves their own leads along the pipeline (`updateLeadStage`); owners and managers approve, reject with a reason, relist or close listings (`moderateListing`). The menus offer only the moves the Functions allow, read from the same table (`functions/src/model/transitions.json`, mirrored in `packages/core` and checked by a test).

## Run

```sh
melos run app:prepare -- <tenant-id>     # tenant file, logos, fonts
cd apps/admin
flutter create . --platforms=web          # once; web/ is not committed
flutter run -d chrome
```

Served by anything but Firebase Hosting (`flutter run`, a plain web server), the admin offers demo accounts over demo data (`lib/src/demo_admin.dart`).

On Firebase Hosting it reads the admin web app's config from `/__/firebase/init.json` (D14), so none is committed, and switches to:

- **Sign-in:** email + password (with *Forgot password?*) or Google (`lib/src/firebase/firebase_auth.dart`). New staff create their own account; it has no role and waits on a screen until an owner adds it. The role comes from the ID token's claims.
- **Tables:** Firestore, scoped by role, paged with `startAfterDocument` (`lib/src/firebase/firestore_admin.dart`; indexes in `firestore.indexes.json`).
- **Changes:** the callable Functions (`lib/src/firebase/callable_actions.dart`).

Deploying and making the first owner: see `infra/terraform/README.md`.
