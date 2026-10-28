# Load tests (P8-s01)

[k6](https://grafana.com/docs/k6/) scripts for the two read paths that take public traffic. Both only read; neither posts a form or calls a Function, so no leads, viewings or tap counts are created.

| Script | What | Load profile | Passes when |
|---|---|---|---|
| `share-pages.js` | Listing, area, agent and home pages, picked from the live `sitemap.xml` (60 / 20 / 10 / 10 %) | ramp to 50 users, hold 5 min | p95 < 800 ms, < 1 % errors |
| `search.js` | Typesense queries shaped like the app's filters (purpose, area, beds, price cap, free text) | ramp to 30 users, hold 5 min | p95 < 300 ms, < 1 % errors |

`PROFILE=smoke` (1 user, 30 s) is the default. CI runs the share pages smoke against the seeded emulator (`smoke-share-pages.sh`) and checks that `search.js` parses.

## Running against dev (Boniface)

Share pages, once they are deployed (`infra/terraform/README.md`, *Share pages*):

```sh
BASE_URL=https://<project-id>-share.web.app PROFILE=load k6 run tools/load/share-pages.js
```

Cloud Run is capped at 3 instances, so the run cannot scale costs up. A run is about 9 minutes and roughly 15,000 requests, which is well inside the free tier. Watch the Cloud Run *Metrics* tab while it runs.

Search, once the Typesense host exists (D4). Use a search-only key scoped to the tenant's collection, and keep it in your shell, never in a file in this repo:

```sh
TYPESENSE_URL=https://<host> TYPESENSE_SEARCH_KEY=<search-only key> COLLECTION=<tenant-id>_listings \
  PROFILE=load k6 run tools/load/search.js
```

Never point either script at prod without agreeing a time with the realtor. Write the results (p95, error rate, instance count) into `docs/security-review.md`.
