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

Not yet covered: the Typesense collection (P2 search), and custom domains on Hosting (needs DNS access, P8).
