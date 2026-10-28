# Privacy notice: template (P6-s04)

**Draft for the realtor and their lawyer to review. Not legal advice.** It describes what the platform actually does as of 28 Oct 2026; the realtor fills in the `[brackets]`. One copy per tenant, published on the share pages and in the app.

---

## How [Realtor name] uses your information

[Realtor name] ("we") runs this website and app to help you find a home to rent or buy. This notice explains what we collect, why, how long we keep it and your rights under Kenya's Data Protection Act, 2019.

**Who we are.** [Realtor legal name], [postal address], [registration number]. Data protection contact: [name or role], [email], [phone]. [ODPC registration number, once registered.]

### What we collect, and why

| When you… | We keep | Why (lawful basis) |
|---|---|---|
| Send an enquiry about a home | Your phone (or email), and your name and message if you give them; which home; when you agreed | To reply about that home (your consent, given with the tick box) |
| Book a viewing | Your name, phone, the home and the time | To arrange and confirm the viewing (your consent) |
| Tap "Call" or "WhatsApp" | Nothing about you: only a count on the home | To know which homes interest people |
| Browse the site or app | No account is needed. Standard technical logs (for example your IP address) are kept by our hosting provider for security | Our legitimate interest in running the service safely |
| Save a search (signed-in users) | The filters you chose and how you want to hear about matches | To send you the alerts you asked for (consent) |

We do not sell your information, and we do not use it for advertising.

### Who sees it

- **Our staff:** the agent responsible for the home, and our managers. Each agent sees only their own enquiries.
- **Service providers** who host the platform for us and may only use the information on our instructions: Google Cloud / Firebase (hosting, database, storage), [search provider, once chosen]. When you choose WhatsApp, your conversation is with WhatsApp (Meta) under their terms.
- **Where it is stored:** on Google Cloud in the European Union (Belgium, region `europe-west1`), outside Kenya. [We rely on: … (the realtor's lawyer to state the safeguard under sections 48–50 of the Act).]

### How long we keep it

Enquiries and viewing requests are deleted automatically **24 months** after you agree (viewing requests 24 months after the viewing time). Counts of calls and WhatsApp taps hold no personal information.

### Your rights

You may ask us to:
- tell you what we hold about you and give you a copy;
- correct it;
- delete it;
- stop contacting you.

Write to [email] or WhatsApp [number] with the phone number or email you used. We answer within [7] days. Our staff can export or delete everything we hold for one phone number or email in one step, so we do not need anything else from you.

If you are not happy with our answer, you may complain to the Office of the Data Protection Commissioner (www.odpc.go.ke).

### Security

All connections are encrypted. Only our staff can read enquiries, each limited to what their role needs, and every change staff make is logged. Photos you see on listings have their location data removed.

### Changes

We will post any change here, with the date. Last updated: [date].

---

### For the developer: where each statement comes from

| Statement | Where it is enforced |
|---|---|
| Consent tick on enquiries and viewings | `createLead` / `bookViewing` require `consent: true`; the share pages form quotes the retention |
| Taps carry no personal data | D13; `logContactTap` |
| Agents see only their own leads | `firestore.rules` (`isOwnAgent`); rules tests |
| 24-month deletion | D12; nightly `purgeExpiredLeads` |
| Export or delete in one step | `dataRequest` callable; admin *Privacy* page |
| Staff changes logged | `audit/` collection |
| EXIF / GPS removed from photos | `processImage` (sharp drops metadata) |
| Stored in europe-west1 | `tenants/<id>.json` → `firebase.region` |
