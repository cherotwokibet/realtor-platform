# Onboarding a realtor (P8-s06)

Seven steps take a signed realtor to a live app, admin and share site. The target is **2 working days** of our time, not counting waits on Google, Safaricom or Meta. Time each step in the table at the end, and fix whatever slowed it down before the next realtor.

Commands run from the repo root in Cloud Shell unless a step says otherwise. `<id>` is the tenant id, for example `acme-realty`, and `<project>` is a project id from the tenant file (`firebase.projects.dev|stage|prod`).

## Before day 1: start the long waits

On the day the contract is signed, start the approvals that nothing can speed up (P0-s08). Each one is in the realtor's name:

- a D-U-N-S number, then the Google Play Console organisation account (and the Apple Developer Program, if they want iOS)
- Safaricom Daraja go-live for their paybill or till, if they take M-Pesa
- Meta Business verification, if they want WhatsApp messages sent for them
- ODPC registration as a data controller (`docs/privacy/odpc-checklist.md`)
- access to their domain's DNS

Collect from the realtor: logos as SVG (full, stacked, mark, plus reverse versions), brand colours and fonts, the office phone and WhatsApp numbers, the domain, a billing account they own, and the names and emails of their staff.

## Step 1. Tenant file (about 2 hours)

```sh
node tools/tenant-cli/src/cli.ts create <id> "<Company name>"
```

This writes `tenants/<id>.json` and placeholder art in `brand/<id>/`. Replace every `TBC` and `example.com` value, the colours and fonts, and the SVGs. Switch off the features they did not buy (`features`). Leave secrets as `secret://` references.

```sh
node tools/tenant-cli/src/cli.ts validate <id>   # schema, assets and colour contrast
node tools/tenant-cli/src/cli.ts prepare <id>    # icons, splash and share images; check how they look
```

Open a pull request with the tenant file and brand folder. CI builds every tenant's Android flavor side by side, and its share pages.

## Step 2. Projects (about 1 hour, plus Google's waits)

Create dev, stage and prod with Terraform, on the realtor's billing account, as `infra/terraform/README.md` describes ("Provisioning a tenant"). Then, once per project:

- turn on Google sign-in in the Firebase console, if they want it (the README says how)
- add the secret values the tenant file names (Secret Manager, by hand)
- add `ops.alertEmails` to the tenant file, so outages reach someone (`docs/operations.md`)

## Step 3. Deploy dev (about 1 hour)

```sh
node tools/tenant-cli/src/cli.ts deploy <id> dev     # Functions, images, Terraform and Hosting
```

Check that the app, admin and share sites open, on mobile data as well as on Wi-Fi.

## Step 4. People and areas (30 minutes)

1. The realtor's owner signs in to the admin once, so their account exists. Then:
   ```sh
   PROJECT=<project> OWNER_EMAIL=<their email> npm --prefix functions run staff:owner
   ```
   From then on, the owner adds managers and agents in the admin (*Team*).
2. Load the starting area guides, which the realtor edits later in the admin (*Areas*):
   ```sh
   PROJECT=<project> npm --prefix functions run areas:load
   ```
   Areas that already exist are left alone. Their stats fill in overnight.

## Step 5. Content (half a day, mostly the realtor's)

In the admin:

- add agent profiles with photos
- import listings with *Import CSV…* (the dialog lists the columns), or create them in the form, then approve them
- publish the site pages (About, Privacy, Terms, FAQ, Contact). The privacy notice comes from `docs/privacy/privacy-notice.md` and the realtor's lawyer
- if M-Pesa is on: set viewing fees, then make one sandbox payment (`docs/mpesa.md`)

Then make a test enquiry and a viewing booking from a phone, and check they reach the leads board.

## Step 6. Apps (about 1 hour, once Play Console exists)

```sh
node tools/tenant-cli/src/cli.ts firebase-config <id> prod --flavor
node tools/tenant-cli/src/cli.ts release <id> --track=internal
```

Read `docs/store-release.md` the first time. Install from the internal track on a mid-range Android phone. Check that the app starts with the realtor's icon and splash, that a shared listing link opens the app, and that saving a search asks to send notifications.

## Step 7. Go live (half a day)

1. Run steps 3 to 5 on prod: `deploy <id> prod`, then `staff:owner` and `areas:load` (add `CONFIRM=<project>`, since prod is guarded). Their listings go in through the admin on prod.
2. DNS: point the bare domain at the share pages, `app.` at the app site and `admin.` at the admin. Publish the site pages before the store release, because the app's About, Privacy and Terms links open them.
3. Promote the store release from internal to closed testing, then to production, in the Play Console.
4. Train staff in two short sessions: managers first, then agents.
5. The first real lead marks go-live. Note the date in the tracker.

## Timing

| Step | Target | Actual | What slowed it down |
|---|---|---|---|
| 1. Tenant file | 2 h | | |
| 2. Projects | 1 h | | |
| 3. Deploy dev | 1 h | | |
| 4. People and areas | 30 min | | |
| 5. Content | half a day | | |
| 6. Apps | 1 h | | |
| 7. Go live | half a day | | |
