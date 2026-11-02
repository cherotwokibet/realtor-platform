# Data protection checklist for a new realtor (P6-s04)

**For the realtor and their lawyer. Not legal advice.** What the platform already does, and what only the realtor can do. Tick each before go-live (P8-s03).

## The realtor does

- [ ] **ODPC registration.** Check with the Office of the Data Protection Commissioner whether registration as a data controller is required (the Data Protection (Registration of Data Controllers and Data Processors) Regulations, 2021 set thresholds and list sectors that must register whatever their size), and register if so. Record the certificate number in the privacy notice.
- [ ] **Data protection contact.** Name the person who answers privacy requests; put their email and phone in the privacy notice.
- [ ] **Privacy notice.** Complete `docs/privacy/privacy-notice.md` with the lawyer, including the safeguard for storage outside Kenya (Google Cloud, EU). Publish it.
- [ ] **Agreement with the platform operator.** A written data processing agreement between the realtor (controller) and Boniface / the platform (processor): instructions only, confidentiality, security, sub-processors (Google Cloud, the search host), deletion at the end of the contract. Fits in the contract template (P8-s04).
- [ ] **Staff.** Every staff account is personal (no shared logins); remove leavers on the admin *Team* page the same day.
- [ ] **Old data.** Decide what to do with leads and contacts in the old system (P2-s06): migrate only what has consent and a known date, delete the rest.
- [ ] **Breach plan.** Who tells the ODPC (within 72 hours of becoming aware) and the people affected, and how. Boniface tells the realtor of any incident without delay.

## The platform already does

- [x] Consent tick, quoted retention and a timestamp on every enquiry and viewing request.
- [x] No personal data from call or WhatsApp taps (D13).
- [x] Automatic deletion after 24 months (D12, `purgeExpiredLeads`).
- [x] Export or delete one person's data in one step (admin *Privacy*, `dataRequest`), audited without their details.
- [x] Least access: agents see only their own leads; managers see all; the public sees only live listings (`firestore.rules`, tested).
- [x] Audit log of staff actions, with no client personal data in it.
- [x] Rate limits on the public forms; no form contents in server logs.
- [x] Encryption in transit; security headers; photo metadata (GPS) stripped.
- [ ] App Check on the public forms: D16, proposed.

## Before each new realtor

- [ ] Copy the privacy notice, fill in their details, publish.
- [ ] Their own Firebase project, on their billing (D1), so their data never shares a database with another realtor's.
- [ ] Their ODPC status and contact recorded in `tenants/<id>.json` notes.
