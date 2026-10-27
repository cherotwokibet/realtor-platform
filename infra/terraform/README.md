# Terraform: one Firebase project per tenant and environment (D1)

`modules/firebase-env` creates, for one tenant and one of dev / stage / prod:

- the GCP project (on the realtor's billing account), with the APIs Firebase, Functions and Secret Manager need
- Firebase on the project, a Firestore database in the tenant's region, a media bucket linked to Firebase Storage
- the repo's `firestore.rules` and `storage.rules`, released
- Android, iOS and web app registrations (their configs become each flavor's `firebase_options`)
- one **empty** Secret Manager secret per `secret://<id>` in the tenant file. Values are added by hand in the console, never through Terraform, so state never holds them.

`tenant/` is the root config. It reads `tenants/<tenant_id>.json` and holds no realtor values.

CI only runs `fmt` and `validate`. Nothing here is ever applied automatically.

## Provisioning a tenant (Boniface, with the realtor's billing account)

```sh
node tools/tenant-cli/src/cli.ts create acme-realty "Acme Realty Ltd"   # scaffold + placeholder art
# edit tenants/acme-realty.json and brand/acme-realty/, then validate
cd infra/terraform/tenant
gcloud auth application-default login
terraform init -backend-config="prefix=acme-realty/dev"
terraform plan  -var tenant_id=acme-realty -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX
terraform apply -var tenant_id=acme-realty -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX
```

If the GCP project already exists (for example you created `rte-realtor-dev` in the console), import it before the first plan, or apply will fail with "already exists":

```sh
terraform import -var tenant_id=<id> -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX module.env.google_project.this <project-id>
```

Do the same for anything else that already exists, such as Firebase on the project (`module.env.google_firebase_project.this projects/<project-id>`) or the Firestore database (`module.env.google_firestore_database.default projects/<project-id>/databases/(default)`).

Repeat with `env=stage` and `env=prod` (each has its own state prefix). The state bucket `realtor-platform-tfstate` must exist first (one per operator, versioned, in a project you own).

Firestore composite indexes come from the repo's `firestore.indexes.json`, the same file the emulator reads.

### Staff admin (P5, D14)

Terraform registers an admin web app, an admin Hosting site (`<project-id>-admin`, output `admin_url`) and email + password sign-in (Identity Platform, free tier up to 50,000 monthly users).

Google sign-in is switched on once per project by hand, so its client secret never enters Terraform state: Firebase console → Authentication → Sign-in method → Add new provider → Google → Enable, pick a support email, Save.

To put the admin online and make the first owner:

```sh
melos run app:prepare -- <tenant-id>
(cd apps/admin && flutter create . --platforms=web --project-name realtor_admin && rm -f test/widget_test.dart && flutter build web --release)
firebase target:apply hosting admin <project-id>-admin --project <project-id>   # once per project
firebase deploy --only hosting:admin,functions --project <project-id>
```

Open `admin_url` and either create an account (email + password) or continue with Google; the account then exists, with no role. Then, once per project:

```sh
PROJECT=<project-id> OWNER_EMAIL=<that email> npm --prefix functions run staff:owner
```

Press *Check again* (or sign out and in) to pick up the owner role. From then on the owner adds staff with `setStaffRole`.

Not yet covered: the Typesense collection (P2 search), and custom domains on Hosting (needs DNS access, P8).
