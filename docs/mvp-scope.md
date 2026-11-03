# MVP scope for Realtime Estates (P0-s07)

What goes live first, what follows, and what waits. Realtime Estates signs this off (section 5). After that, anything new is a change request (section 4).

**Status on 3 Nov 2026.** "Built" means merged and running on dev (rte-realtor-dev). "Go-live" means the work in section 3.

## 1. Must have at go-live

| Area | What the customer or staff member can do | Status |
|---|---|---|
| **Find a home** | Search to rent or buy by area, budget, bedrooms, type and amenities. Type in plain English or Swahili ("2br Kilimani under 60k with parking"). See results as a list or on a map, and draw an area on the map. Every search is a shareable link. | Built |
| **See a home** | Photos and video, price, key facts, description, a "Verified" badge with its date, the agent, and similar homes. Share pages load in 0.9 s on 4G. | Built |
| **Contact** | WhatsApp with the listing pre-filled, call, an enquiry form with data protection consent, and booking a viewing in a free slot. Every contact is logged as a lead. | Built |
| **Area guides** | 16 Nairobi areas, each with its description, typical rent and live listings. | Built |
| **Accounts and alerts** | Save homes on the phone. Sign in by email link. Get an in-app alert within 5 minutes when a new home matches a saved search. | Built (deploy pending) |
| **Apps** | An Android app and a web app (app.realtimeestates.co.ke): back navigation, under 25 MB, listings in 2.3 s on a Samsung A25 over 4G. | Built; store release at go-live |
| **Admin** | Roles (owner, manager, agent). Listings: create, edit, upload, approve or reject, feature, CSV import, "Confirm still available". Leads board with reply-time tracking. Viewings calendar: confirm, reschedule, no-show, agent time off. Agent profiles, reviews moderation, site pages (About, Privacy, Terms, FAQ, Contact), monthly reports with CSV. | Built |
| **Trust and safety** | Listings expire after 30 days unless re-confirmed. Duplicate-photo flags. Rate limits on forms. Security rules tested on every collection. | Built |
| **Data protection** | Consent on every form, 24-month lead retention, data export and delete requests, privacy notice template. | Built; ODPC registration by the realtor |
| **Operations** | Uptime checks with email alerts, a load test (p95 3.6 ms, 0 errors), and backups. | Built |

## 2. Should have, soon after go-live

| Item | Why it waits | Depends on |
|---|---|---|
| Push and email alerts | The in-app alert works now. Push needs a VAPID key and email needs a sender. | External set-up |
| M-Pesa viewing fees | The backend is built and tested (`docs/mpesa.md`). It needs a fee field on listings, a "Pay with M-Pesa" button, and Safaricom keys. | Daraja sandbox, then go-live (P0-s08) |
| iOS app | Same code base, built from the same flavors. | Apple Developer organisation account |
| Viewing reminders by SMS or WhatsApp | A message sender is needed. | WhatsApp Business verification |
| Moving the old app's listings and users | A one-off import into the new shape. | An export of the old vendor's Firebase project |

## 3. Go-live checklist (P8-s03)

1. **Stores.** Play Console in Realtime Estates' name (D-U-N-S), then `tenant release realtime-estates --track=internal`, then closed testing, then production.
2. **Domains.** `realtimeestates.co.ke` goes to the share pages, `app.` to the web app and `admin.` to the admin. Publish the site pages in the admin before the store release.
3. **Prod deploy.** `tenant deploy realtime-estates prod`, then seed the areas, then create the staff accounts.
4. **Staff training.** Two sessions: managers, then agents.
5. **First live lead received.** That marks go-live.

## 4. Could have, and won't have now

- **Could, as priced extras:** in-app chat (WhatsApp hand-off works now); deposits and featured-ad fees by M-Pesa; push campaigns to customer segments; PDF reports; area trend charts; an AI copywriter (the current one is rule-based).
- **Won't have in this release:** short-stay bookings with calendars and payment; tenant and rent management for landlords; a mortgage calculator or bank partnerships; a multi-agency marketplace.

Any change to sections 1 to 3 after sign-off is a change request with its own estimate. Section 1 of `docs/commercial/pricing-and-contract.md` prices the extras.

## 5. Sign-off

| | Name | Signature | Date |
|---|---|---|---|
| Realtime Estates Ltd | | | |
| Boniface (platform) | | | |
