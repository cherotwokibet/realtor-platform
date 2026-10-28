# Sales demo: a prospect's brand in a meeting (P8-s05)

The demo tenant (`demo-homes`) is a complete fictional realtor: 16 Nairobi and commuter-town area guides, three agents, a spread of rent and sale listings, leads, viewings and an audit log. The app and the admin both run on built-in demo data in the browser, with no Firebase, no accounts and no cost. `tenant rebrand` puts a prospect's name and colours on it in about a minute, so they can see *their* app.

## Before the meeting (once, on the laptop)

```sh
cd ~/realtor-platform && git pull
npm --prefix tools/tenant-cli ci
flutter pub get
(cd apps/realtor_app && flutter create . --platforms=web --project-name realtor_app)
(cd apps/admin && flutter create . --platforms=web --project-name realtor_admin && rm -f test/widget_test.dart)
```

Check that the plain demo runs: `node tools/tenant-cli/src/cli.ts prepare demo-homes`, then `flutter run -d chrome` in `apps/realtor_app` and `apps/admin`.

## In the meeting

1. Ask for their name and main brand colour. A photo of their signboard or business card is enough. A second colour is optional.
2. Rebrand. Use a short id; it is only for this laptop:
   ```sh
   node tools/tenant-cli/src/cli.ts rebrand acme-demo "Acme Realty" --from demo-homes --primary "#B00020" --accent "#F2A541"
   node tools/tenant-cli/src/cli.ts prepare acme-demo
   ```
   If their colour is too light for white text or for links, it is darkened just enough and the command says so ("adjusted: …"). That is a talking point: the platform keeps every realtor's app readable (WCAG AA).
3. Run both and walk through:
   - **App** (`apps/realtor_app`, `flutter run -d chrome`): search by area and budget, a listing with photos and the *Verified* badge, *Ask about this home*, *Book a viewing*, WhatsApp.
   - **Admin** (`apps/admin`, `flutter run -d chrome`, pick *Demo Owner*): new leads with how long they have waited, an agent moving a lead on, a manager approving a listing, confirming a listing is still available, the Team page with each agent's typical reply time, the photo-match flag, the Privacy page, the audit log.
4. Switching prospects is the same two commands with another id.

The logo is a placeholder house mark in their colours. Their real artwork goes in at onboarding (`tenant create`, P8-s06).

## After the meeting

Remove the demo files. They are never committed:

```sh
rm -rf tenants/acme-demo.json brand/acme-demo
node tools/tenant-cli/src/cli.ts prepare demo-homes
```

## What it does not do

- Nothing is provisioned or deployed: no Firebase project, no domain, no store listing.
- The prospect's name stays on the laptop; nothing about them is sent anywhere.
