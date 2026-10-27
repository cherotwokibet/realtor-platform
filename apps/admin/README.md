# Admin / CRM (Phase 5)

Flutter web app for staff, sharing `packages/core` and `packages/ui` with the customer app. The information architecture comes from the vendor's Miro wireframes (`Real estate LTD.pdf`, 50 frames). The vendor admin code is reference only (D3, D8).

## Roles

Staff roles are custom claims set by a Function (`role`: owner / manager / agent, plus `agentId` for agents). `StaffUser` in `packages/core` reads them and decides what each role opens; `firestore.rules` enforces the same split on the data.

| | Leads | Listings | Audit log |
|---|---|---|---|
| Owner, manager | all | all | yes |
| Agent | own | own | no |

Every table pages on the server (`startAfter` + `limit`), newest first. Changes (lead stage, approving a listing) go through the Functions, which write the audit log in the same transaction (D7).

## Run

```sh
melos run app:prepare -- <tenant-id>     # tenant file, logos, fonts
cd apps/admin
flutter create . --platforms=web          # once; web/ is not committed
flutter run -d chrome
```

Until Firebase Auth is wired, the sign-in screen offers demo accounts over demo data (`lib/src/demo_admin.dart`).
