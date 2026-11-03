# Pricing and contract template (P8-s04)

A starting point for Boniface and a Kenyan lawyer, not legal advice. The figures below were set on 3 Nov 2026 from Kenyan market research (section 7); a lawyer reviews the template before the first signature. Nothing here is agreed with any realtor. Realtor-specific details (names, amounts, dates) go into the signed copy only, never into this repo.

## 1. What the realtor buys

A branded property platform run for them: their own Android/iOS app, web app, share pages (`share.<their domain>`), and staff admin, all from one codebase, configured by their tenant file.

| | Starter | Growth | Pro |
|---|---|---|---|
| App, web app, share pages, admin | ✓ | ✓ | ✓ |
| Staff accounts (owner, managers, agents) | up to 5 | up to 15 | up to 40 |
| Live listings | up to 150 | up to 600 | up to 2,000 |
| Leads, viewings, reviews, verified listings, area guides, reports | ✓ | ✓ | ✓ |
| Off-plan projects (`offPlan`) | – | ✓ | ✓ |
| Conversational search (`aiSearch`) | – | ✓ | ✓ |
| M-Pesa payments (`mpesa`), featured listings (`ads`) | – | – | ✓ |
| In-app chat (`chat`) | – | – | ✓ |
| Support response (business hours, EAT) | 2 working days | 1 working day | 4 hours |

Tier features map one-to-one to the switches in `tenants/<id>.json`, so moving tier is a tenant-file change and a deploy, not new code.

**Prices** (KES, before VAT; add 16% VAT once Boniface is VAT-registered):

| | Starter | Growth | Pro |
|---|---|---|---|
| One-time setup | 120,000 | 180,000 | 250,000 |
| Monthly subscription | 15,000 | 30,000 | 55,000 |
| Yearly, paid upfront (2 months free) | 150,000 | 300,000 | 550,000 |

- **Setup covers:** onboarding (P8-s06): brand assets, store listings in the realtor's accounts, importing up to 200 existing listings, two staff training sessions, and the first release to Google Play and the App Store. Pro's higher setup includes M-Pesa (Daraja) go-live and the chat set-up.
- **Moving tier:** up or down at the next billing month; an upgrade pays the difference in setup fee.
- **Launch offer:** the first three realtors get 50% off the setup fee in exchange for a public case study.
- **Extras:**
  - Second brand or domain: setup 60,000, plus 40% of the tier's monthly fee.
  - Custom features: 40,000 per developer-day, quoted in writing before work starts.
  - Extra training: 20,000 per half-day session.
  - Importing more than 200 listings: 10,000 per further 500.
- **Billing:** monthly or yearly in advance, by M-Pesa Paybill or bank transfer, due within 14 days of the invoice.
- **Price changes:** at most once a year, with 60 days' notice, capped at Kenya's CPI inflation for the previous 12 months plus 5 points.

## 2. Cloud and third-party costs: on the realtor's bill

The realtor's Firebase/Google Cloud projects (dev, staging, prod) use **the realtor's own billing account**. We never pay for, hold, or change their billing (see the repo rules). This keeps costs transparent and makes leaving simple.

- Typical costs: Firestore, Storage, Hosting, Functions, Cloud Run (share pages, video), and Typesense if used. Most small realtors stay near the free tiers; budget alerts per tenant are part of observability (P8-s02).
- Paid by the realtor directly: domain, Apple Developer (yearly), Google Play (one-time), SMS if they turn it on, M-Pesa and WhatsApp Business charges.
- Store accounts are **in the realtor's name** (D-U-N-S, P0-s08); we are added as admins.

## 3. Service levels

- **Availability target:** 99.5% a month for the share pages, web app, and Functions, measured by uptime checks (P8-s02). Excludes planned maintenance announced 48 h ahead, outages of Google Cloud/Firebase, app stores, Safaricom, or Meta, and the realtor's own DNS.
- **Severity:**
  - S1: site or app down, or payments failing. Response within the tier's support time, also out of hours for Pro.
  - S2: a main feature broken.
  - S3: everything else.
- **Service credit:** 5% of that month's subscription for each full 0.5% below target, up to 25%. The realtor claims it within 30 days of the month's end. Credits are the only remedy for missed targets.
- **Backups:** daily Firestore exports kept for 30 days. Restore on request.

## 4. Data ownership and protection

- **The realtor owns their data:** listings, photos, leads, customers, reviews, and reports. Under the Data Protection Act 2019, the realtor is the **data controller** and we are the **data processor**. A data processing agreement (DPA) is attached, built from `docs/privacy/` (privacy notice, ODPC checklist): purpose limits, staff confidentiality, sub-processors (Google Cloud/Firebase, Typesense if used, Safaricom, Meta), breach notice within 48 h, and help with subject requests (the admin's Privacy page).
- Retention follows D12 (lead data 24 months from consent) unless the realtor sets a shorter period.
- **On exit:**
  - Within 30 days of the end date we hand over a full export (Firestore JSON, Storage files) and transfer the Firebase projects, which are already on their billing.
  - We then delete our copies and certify deletion.
  - The store listings stay theirs.
- **The platform stays ours:** the code, tools, and design system remain ours. The realtor gets a licence to use them while the subscription runs. Their brand, logo, content, and domain stay theirs.

## 5. Term, changes and ending

- Minimum term 12 months (the setup fee is priced on it), then rolling monthly. Either side may end it with 60 days' written notice after the minimum term.
- Late payment: after 30 days overdue, written notice. After 60 days, the service may be suspended (data kept, not deleted).
- Liability capped at the fees paid in the previous 12 months. No liability for lost profits or for third-party outages.
- Kenyan law. Disputes go first to mediation in Nairobi.

## 6. Checklist before signing

- [x] Figures set (3 Nov 2026, section 1 and section 7).
- [ ] Lawyer has reviewed this template and the DPA.
- [ ] Realtor's billing account linked to their projects (they do this in the console).
- [ ] Store accounts and domain in the realtor's name (P0-s08).
- [ ] ODPC registration status known (`docs/privacy/odpc-checklist.md`).

## 7. How the figures were set (research, 3 Nov 2026)

The figures in this document are judgement calls, not survey results: Kenyan vendors rarely publish prices, and most figures below are vendor claims.

| Comparison | What it costs | Source |
|---|---|---|
| Listing portals (agent visibility on someone else's site) | about KES 3,500 to 10,000 a month | Nation (Property24 KES 3,480/month, OLX 10,500/month; undated); How We Made It in Africa (6,500 to 9,500/month) |
| Property-management software for agents and landlords | about KES 3,500 to 9,800 a month | Kenyan vendor pages via search |
| Custom real estate app from a Nairobi studio | KES 300,000 for a catalogue with booking; 600,000 to 900,000 with CRM and commissions | kolonell.com 2026 cost guide |
| Upkeep of a custom app | 15 to 20% of the build cost every year | several 2026 cost guides |
| Generic white-label app builders (no real estate features) | USD 199 to 497 a month for the agency | AppMySite, HighLevel |
| SaaS uptime credits | 99.5% target with about 5% credit per band, capped near 20 to 25% | Kerio, Trilogy SLAs |

**Reasoning:**
- **Above a portal, below a build.** A portal sells reach on someone else's site. This is the realtor's own branded app, web app, share pages and admin, run and updated for them.
  - Over three years, a mid-range custom build (KES 600,000 plus 20% upkeep a year) costs about KES 960,000, with no SLA or new features.
  - Growth over the same three years costs about KES 1.26 million including setup, and includes hosting operations, updates, the SLA and new features.
  - Starter costs about KES 660,000.
- **Starter sits near two portal subscriptions.** It is for a small agency's first own app.
- **Setup covers real time.** About two days of onboarding, store review rounds and imports. The launch offer halves it for the first three realtors, to win references.
- **Credits follow the market.** They were lowered from the first draft's 10% a band, capped at 50%, to the common 5% a band, capped at 25%.
- **Cloud costs stay on the realtor's own bill (section 2).** A small realtor on Firebase usually pays a few thousand shillings a month or less.

Review after the first three clients: if all three choose Growth or above, raise Starter or tighten its limits.

Sources:
- [Nation: OLX and property firm in discount deal for agents](https://nation.africa/kenya/business/olx-and-property-firm-in-discount-deal-for-agents--371690)
- [How We Made It in Africa: Kenyan property website](https://www.howwemadeitinafrica.com/p/kenyan-property-website-gained-success-by-being-ahead-of-the-game)
- [kolonell.com: real estate listings and CRM app cost, Nairobi 2026](https://kolonell.com/en/blog/real-estate-listings-crm-app-cost-nairobi-2026)
- [AppMySite agency pricing](https://www.appmysite.com/agency-app-builder-pricing/)
- [Kerio Cloud SLA](https://www.gfi.com/legal/kerio-cloud-sla)
- [Trilogy SaaS service level addendum](https://saasserviceleveladdendum.trilogy.com)
