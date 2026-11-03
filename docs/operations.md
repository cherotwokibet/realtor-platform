# Operations (P8-s02)

What watches each tenant's sites, who hears about problems, and what to do first.

## What is watched

`tenant deploy <id> <env> --only=infra` creates, in each tenant project:

| Check | URL | How often |
|---|---|---|
| App | `https://<project>-app.web.app/` | every 5 minutes, from 3 regions |
| Admin | `https://<project>-admin.web.app/` | every 5 minutes, from 3 regions |
| Share pages | `https://<project>-share.web.app/sitemap.xml` (goes through Cloud Run and Firestore) | every 5 minutes, from 3 regions |

A site counts as down when its check fails for 10 minutes. Each check has an alert policy named `<tenant> <env> <site> is down`.

Results are in the Google Cloud console under **Monitoring → Uptime checks**. These checks are within Cloud Monitoring's free allowance.

## Who is told

Add the people to the tenant file, then run `--only=infra` again:

```json
"ops": { "alertEmails": ["you@example.com"] }
```

- **Up to 5 addresses.** Google sends each a confirmation the first time; alerts only start once the address is confirmed.
- **Leave `ops` out** to keep the checks without emails. Dev usually needs none.
- **Prod** should alert at least Boniface, plus the realtor's own technical contact if they have one.

## When an alert comes

1. Open the site yourself, on mobile data as well as Wi-Fi.
2. **Share pages down:** in Cloud Run → `share-pages` → Logs, look at the last errors. A bad image can be rolled back by deploying the previous commit with `--only=images,infra`.
3. **App or admin down:** check Hosting → Release history and roll back to the previous release with one click.
4. **Still down after a rollback:** check the [Google Cloud status page](https://status.cloud.google.com) and the Firebase status page. Outages there are excluded from the service levels in `docs/commercial/pricing-and-contract.md`.
5. Note the start and end times; they decide any service credit.

## Not covered yet

- **Budget alerts:** they live on the realtor's billing account, which we never touch. The realtor or Boniface sets them in the console.
- **Crash reports:** Crashlytics for the phone apps, and Sentry for the web, come with the store release (P4-s07).
