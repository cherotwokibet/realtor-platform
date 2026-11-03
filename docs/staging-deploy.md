# Staging follows main (P0-s05)

`.github/workflows/deploy-staging.yml` deploys the tenant's **stage** project every night at 02:00 Nairobi time, when main has changed that day. It runs the same command as a hand deploy:

```sh
tenant deploy realtime-estates stage --yes
```

That covers functions, images, infra and web. The Terraform plan check still refuses billing changes, deletes and foreign images. You can also start a run by hand: **Actions → Deploy staging → Run workflow**, ticking "force" to deploy without new commits.

The workflow is **off** until the two repository variables below are set. It signs in to Google Cloud with **Workload Identity Federation**: GitHub proves which repository and branch is asking, so no key file exists anywhere.

**GitHub Actions minutes:** a run takes about 15 to 20 minutes, only on days main changed. That is about 400 to 600 minutes a month at most, against GitHub's 2,000 free minutes for a private repository.

## One-time setup (Boniface, in Cloud Shell)

### 1. Create the stage project with a first hand deploy

```sh
cd ~/realtor-platform && git pull
node tools/tenant-cli/src/cli.ts deploy realtime-estates stage --billing=<the realtor's billing account>
```

Terraform creates `rte-realtor-stage` on the realtor's billing account (D1), then deploys everything as on dev.

### 2. Let GitHub's main branch deploy to that project, and nothing else

```sh
P=rte-realtor-stage
N=$(gcloud projects describe $P --format='value(projectNumber)')
REPO=cherotwokibet/realtor-platform

gcloud iam workload-identity-pools create github --project=$P --location=global --display-name="GitHub Actions"
gcloud iam workload-identity-pools providers create-oidc main-branch --project=$P --location=global \
  --workload-identity-pool=github --issuer-uri=https://token.actions.githubusercontent.com \
  --attribute-mapping='google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref' \
  --attribute-condition="assertion.repository=='$REPO' && assertion.ref=='refs/heads/main'"

gcloud iam service-accounts create stage-deployer --project=$P --display-name="Staging deploys from GitHub main"
SA=stage-deployer@$P.iam.gserviceaccount.com
gcloud iam service-accounts add-iam-policy-binding $SA --project=$P --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/projects/$N/locations/global/workloadIdentityPools/github/attribute.repository/$REPO"

# What a full deploy needs in the stage project. Terraform manages IAM and
# services there, so this is owner of *this project only*; dev and prod are untouched.
gcloud projects add-iam-policy-binding $P --member=serviceAccount:$SA --role=roles/owner
# Terraform state for realtime-estates/stage lives in the shared state bucket.
gcloud storage buckets add-iam-policy-binding gs://realtor-platform-tfstate --member=serviceAccount:$SA --role=roles/storage.objectAdmin
```

The deployer can only be used by this repository's **main** branch. A pull request or another branch can't get its token.

### 3. Tell the workflow where to sign in

On GitHub: **Settings → Secrets and variables → Actions → Variables**. These are variables, not secrets: they are names, not keys.

| Variable | Value |
|---|---|
| `STAGE_WIF_PROVIDER` | `projects/<N>/locations/global/workloadIdentityPools/github/providers/main-branch` |
| `STAGE_DEPLOY_SA` | `stage-deployer@rte-realtor-stage.iam.gserviceaccount.com` |
| `STAGE_TENANT` | optional; defaults to `realtime-estates` |

### 4. Check it

Go to **Actions → Deploy staging → Run workflow**, tick force and run it. The last line should be `✓ deployed realtime-estates to rte-realtor-stage at <commit>`.

## Turning it off

Delete the `STAGE_WIF_PROVIDER` variable. Every run is then skipped. To cut access entirely:

```sh
gcloud iam workload-identity-pools delete github --project=rte-realtor-stage --location=global
```

## Prod

Prod is never deployed automatically. A person runs `tenant deploy realtime-estates prod` after checking stage.
