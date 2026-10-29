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

Cloud Functions (2nd gen) service agents get the roles a first Functions deploy needs (`google_project_iam_member.functions_agents`): without them `firebase deploy --only functions` stops with "We failed to modify the IAM policy for the project", or `onListingPhoto` fails with *Permission "storage.buckets.get" denied … the Eventarc service account* (the Eventarc agent's own role, which Google grants late on a fresh project). The bindings are additive, so granting them by hand with the `gcloud` commands the CLI prints is safe; a later apply just finds them in place.

**Quota project.** Identity Platform (`google_identity_platform_config.auth`) refuses user credentials without a quota project: *"identitytoolkit.googleapis.com API requires a quota project"*. For an existing project, set it for the session before `plan`/`apply`, and clear it afterwards (it must not point at a project that does not exist yet when you create a new one):

```sh
export GOOGLE_BILLING_PROJECT=<project-id> USER_PROJECT_OVERRIDE=true
terraform plan ... && terraform apply ...
unset GOOGLE_BILLING_PROJECT USER_PROJECT_OVERRIDE
```

For a brand-new project, the first apply creates the project and everything but the sign-in config; run the same plan/apply again with the two variables set to finish it.

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

### Customer web app

Terraform makes a Hosting site `<project-id>-app` linked to the customer web app, so the app reads its Firebase config from `/__/firebase/init.json` (none is committed). There it shows live listings from Firestore and sends enquiries, viewing requests and taps to the Functions; anywhere else it runs on demo data. In Cloud Shell, from `~/realtor-platform`:

```sh
node tools/tenant-cli/src/cli.ts prepare <id>
(cd apps/realtor_app && flutter create . --platforms=web --project-name realtor_app)
node tools/tenant-cli/src/cli.ts web <id>
(cd apps/realtor_app && flutter build web --release --wasm)
firebase target:apply hosting app <project-id>-app --project <project-id>   # once per project
firebase deploy --only hosting:app --project <project-id>
```

Open `app_url`. Search reads every live listing of the chosen purpose and filters in the browser, which is fine for a few hundred homes; Typesense (D4) replaces it when set up.

### Share pages (D2)

Terraform makes an Artifact Registry repo (`share-pages`, output `share_pages_repo`; it keeps the newest 5 images) and a Hosting site (`<project-id>-share`, output `share_url`) whose every path is rewritten to the `share-pages` Cloud Run service. The service exists only once `share_pages_image` is set, so it takes two applies. In Cloud Shell, from `~/realtor-platform`:

```sh
cd infra/terraform/tenant
terraform apply -var tenant_id=<id> -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX   # makes the repo
REPO=$(terraform output -raw share_pages_repo)
cd ../../..
TAG=$(git rev-parse --short HEAD)
gcloud auth configure-docker europe-west1-docker.pkg.dev --quiet
docker build -f apps/share_pages/Dockerfile --build-arg TENANT=<id> -t "$REPO/share-pages:$TAG" .
docker push "$REPO/share-pages:$TAG"
cd infra/terraform/tenant
terraform apply -var tenant_id=<id> -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX \
  -var share_pages_image="$REPO/share-pages:$TAG"
cd ../../..
firebase target:apply hosting share <project-id>-share --project <project-id>   # once per project
firebase deploy --only hosting:share --project <project-id>
```

The share pages send enquiries, viewing requests and taps to the Functions' twins (`shareCreateLead`, `shareBookViewing`, `shareLogContactTap`, D16), which only the `share-pages` service account may call. Deploy the Functions before a share pages image that expects them.

App Check (D16) starts in watch mode: each public callable logs `{"appCheck":"verified"|"missing"}`. To enforce, put `ENFORCE_APP_CHECK=createLead,bookViewing,logContactTap` (or `all`) in `functions/.env.<project-id>` and deploy the Functions; delete the line to switch back.

Open `share_url`: `/` lists live homes, `/robots.txt` and `/sitemap.xml` answer. Re-deploying is the same build, push and second apply with a new tag; the Hosting deploy is needed only when the `share` block of `firebase.json` changes. Use a new tag every time (the commit), never `latest`, so the Cloud Run revision always changes.

### Video transcoder (D15)

Video uploads are turned into HLS by the Cloud Run job `transcode-video`; until its image is deployed they are refused with a note on the listing ("videos are not switched on for this site yet"). The image goes in the same Artifact Registry repo. In Cloud Shell, from `~/realtor-platform`:

```sh
cd infra/terraform/tenant
REPO=$(terraform output -raw share_pages_repo)
cd ../../..
TAG=$(git rev-parse --short HEAD)
docker build -f functions/transcode.Dockerfile -t "$REPO/transcode-video:$TAG" functions
docker push "$REPO/transcode-video:$TAG"
cd infra/terraform/tenant
terraform apply -var tenant_id=<id> -var env=dev -var billing_account=XXXXXX-XXXXXX-XXXXXX \
  -var share_pages_image=<current share pages image> -var transcode_image="$REPO/transcode-video:$TAG"
```

Every later apply must pass both images, or the plan removes the service and the job: read the plan for destroys first. The job has 2 CPU, 2 GiB and 30 minutes, runs only when a video arrives and costs nothing idle.

Not yet covered: the Typesense collection (P2 search), and custom domains on Hosting (needs DNS access, P8).
