# Pricing and contract template (P8-s04)

A starting point for Boniface and a Kenyan lawyer, not legal advice. Every figure marked **[set]** is a proposal for Boniface to decide; nothing here is agreed with any realtor. Realtor-specific details (names, amounts, dates) go into the signed copy only, never into this repo.

## 1. What the realtor buys

A branded property platform run for them: their own Android/iOS app, web app, share pages (`share.<their domain>`), and staff admin, all from one codebase, configured by their tenant file.

| | Starter | Growth | Pro |
|---|---|---|---|
| App, web app, share pages, admin | ✓ | ✓ | ✓ |
| Staff accounts (owner, managers, agents) | up to 5 | up to 15 | up to 40 **[set]** |
| Live listings | up to 150 | up to 600 | up to 2,000 **[set]** |
| Leads, viewings, reviews, verified listings, area guides, reports | ✓ | ✓ | ✓ |
| Off-plan projects (`offPlan`) | – | ✓ | ✓ |
| Conversational search (`aiSearch`) | – | ✓ | ✓ |
| M-Pesa payments (`mpesa`), featured listings (`ads`) | – | – | ✓ |
| In-app chat (`chat`) | – | – | ✓ |
| Support response (business hours, EAT) | 2 working days | 1 working day | 4 hours |

Tier features map one-to-one to the switches in `tenants/<id>.json`, so moving tier is a tenant-file change and a deploy, not new code.

**Proposed prices [set]:**

- One-time setup: covers onboarding (P8-s06), brand assets, store listings, importing existing listings, and staff training. Suggest a setup fee that covers about 2 working days of onboarding plus store and review time.
- Monthly subscription per tier, billed in KES, invoiced monthly or yearly (yearly at 2 months free).
- Extras at cost or a fixed fee: a second brand/domain, custom features, extra training days.

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
- **Service credit [set]:** for example, 10% of that month's fee for each full 0.5% below target, up to 50%. Credits are the only remedy for missed targets.
- **Backups:** daily Firestore exports kept for 30 days **[set]**. Restore on request.

## 4. Data ownership and protection

- **The realtor owns their data:** listings, photos, leads, customers, reviews, and reports. Under the Data Protection Act 2019, the realtor is the **data controller** and we are the **data processor**. A data processing agreement (DPA) is attached, built from `docs/privacy/` (privacy notice, ODPC checklist): purpose limits, staff confidentiality, sub-processors (Google Cloud/Firebase, Typesense if used, Safaricom, Meta), breach notice within 48 h, and help with subject requests (the admin's Privacy page).
- Retention follows D12 (lead data 24 months from consent) unless the realtor sets a shorter period.
- **On exit:**
  - Within 30 days **[set]** we hand over a full export (Firestore JSON, Storage files) and transfer the Firebase projects, which are already on their billing.
  - We then delete our copies and certify deletion.
  - The store listings stay theirs.
- **The platform stays ours:** the code, tools, and design system remain ours. The realtor gets a licence to use them while the subscription runs. Their brand, logo, content, and domain stay theirs.

## 5. Term, changes and ending

- Minimum term 12 months **[set]**, then rolling monthly. Either side may end it with 60 days' written notice after the minimum term.
- Price changes apply with 60 days' notice, at most once a year.
- Late payment: after 30 days overdue, written notice. After 60 days, the service may be suspended (data kept, not deleted).
- Liability capped at the fees paid in the previous 12 months. No liability for lost profits or for third-party outages.
- Kenyan law. Disputes go first to mediation in Nairobi.

## 6. Checklist before signing

- [ ] Figures marked **[set]** decided.
- [ ] Lawyer has reviewed this template and the DPA.
- [ ] Realtor's billing account linked to their projects (they do this in the console).
- [ ] Store accounts and domain in the realtor's name (P0-s08).
- [ ] ODPC registration status known (`docs/privacy/odpc-checklist.md`).
