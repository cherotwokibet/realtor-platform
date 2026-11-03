# M-Pesa payments (P6-s01)

Customers pay viewing fees with M-Pesa Express (STK Push): they confirm on their own phone, and the money goes straight to the realtor's paybill or till. We never hold money.

## How it works

1. **Start.** `payments-startViewingPayment` takes a viewing id and a phone number.
   - The amount comes from the viewing (`feeKES`, set when it was booked), never from the app.
   - It writes `payments/viewing-fee_<viewingId>` as **pending** and asks Daraja to push the prompt to the phone.
   - A second tap within 2 minutes reuses the prompt already on the phone. A paid viewing can't be paid again.
2. **Callback.** Safaricom posts the result to `payments-mpesaCallback`.
   - The callback URL carries a random token stored on that payment, so only Safaricom's answer for that push can settle it.
   - If paid, the payment becomes **paid** with the M-Pesa receipt, and the viewing's `paymentId` points at it.
   - If cancelled or failed, it says why.
   - Repeated callbacks change nothing.
   - An amount different from the payment's is never marked paid: it is marked failed, with a note to check by hand.
3. **Reconciliation.** Every 5 minutes, `payments-reconcilePayments` asks Daraja about any push still pending after 3 minutes, so a lost callback never leaves money unrecorded. After 24 hours with no answer, it marks the payment failed. Payments settled this way have no receipt number; the M-Pesa statement has it.

Managers can read `payments`. No client can write to it (see `firestore.rules`).

## Switching it on for a project

Use Cloud Shell. Do **sandbox first**, on dev.

1. **Get the keys.**
   - **Sandbox:** create an app on the Safaricom developer portal (developer.safaricom.co.ke) and note its consumer key and secret. Sandbox uses shortcode `174379` and the passkey shown on the portal's M-Pesa Express simulator.
   - **Production:** the realtor applies for Daraja go-live (P0-s08). Safaricom then issues production keys and a passkey for their own paybill or till.
2. **Put the three secrets in Secret Manager.** Type each value at the prompt; never put it in a file or a command line.
   ```sh
   cd ~/realtor-platform/functions
   npx firebase functions:secrets:set MPESA_CONSUMER_KEY --project <project-id>
   npx firebase functions:secrets:set MPESA_CONSUMER_SECRET --project <project-id>
   npx firebase functions:secrets:set MPESA_PASSKEY --project <project-id>
   ```
3. **Turn the functions on.** Create `functions/.env.<project-id>`. It is local and never committed:
   ```
   MPESA_ENV=sandbox
   MPESA_SHORTCODE=174379
   MPESA_TYPE=paybill
   ```
   For production, set `MPESA_ENV=production`, the realtor's paybill or till number, and `MPESA_TYPE=till` for a Buy Goods till.
4. **Deploy and switch on.**
   - Run `node tools/tenant-cli/src/cli.ts deploy <id> <env> --only=functions`, which deploys `payments-*`.
   - Set `"mpesa": true` in the tenant file's `features`, then deploy with `--only=infra` so `config/tenant` follows.
5. **Test in sandbox:** start a payment for a viewing with a fee. In sandbox, Safaricom's test numbers accept the prompt, and the payment should turn **paid** within a minute.

Without `MPESA_ENV`, the payment functions are not deployed at all, so deploys never need these secrets.

## Not done yet

- **Setting a fee:** listings don't carry a viewing fee yet, so `bookViewing` still sets `feeKES: 0`. The next step adds an optional viewing fee to the listing form, and a "Pay with M-Pesa" button on the booking confirmation in the app and on the share pages.
- **Deposits and featured-ad fees:** these use the same start/callback/reconcile path with their own amount rules.
- **Receipts by SMS or email:** these need a sender, which is external set-up.
