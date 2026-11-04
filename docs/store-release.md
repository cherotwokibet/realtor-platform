# Store release: one command to Google Play testing (P4-s07)

```sh
node tools/tenant-cli/src/cli.ts release <id>                  # internal testing
node tools/tenant-cli/src/cli.ts release <id> --track=closed   # closed testing
node tools/tenant-cli/src/cli.ts release <id> --dry-run        # show the steps and listing, touch nothing
```

Run it in Cloud Shell from a clean checkout of `main`, signed in to `gcloud` and `firebase` with an account that can read the tenant's **prod** project.

Cloud Shell has no Android SDK. Run `source tools/cloudshell-android.sh` first, once per Cloud Shell session (`docs/android-build.md`).

The command does six things:
1. Builds that tenant's Android App Bundle from the current commit, with the prod Firebase settings and a version code that always goes up.
2. Signs the bundle with the tenant's **upload key**.
3. Uploads the bundle to Google Play.
4. Puts it on the internal or closed testing track.
5. Updates the store listing text.
6. Commits everything as one Play edit. If anything fails before the commit, nothing changes in the Play Console.

**Production is never released from here.** Promote a tested release to production in the Play Console.

The listing comes from the tenant file:
- **Title:** the app name.
- **Short description:** built from the tagline and the purposes the tenant has switched on (rent, buy, short stay).
- **Full description:** one bullet for each feature that is switched on.

To write it yourself instead, add this to `tenants/<id>.json`:

```json
"store": {
  "language": "en-GB",
  "listing": { "title": "…", "shortDescription": "…", "fullDescription": "…" }
}
```

Play's limits are 30, 80 and 4,000 characters, and the command checks them before building.

## One-time setup per realtor

The realtor or Boniface does this, never Claude. It needs the realtor's Play Console account (organisation account, D-U-N-S: P0-s08).

1. **Create the app in the Play Console** with the package name from `apps.androidId` in the tenant file. Turn on **Play App Signing**: Google keeps the key that signs what users install, and we keep only an *upload key*.
2. **Make the upload key** on a trusted computer and keep a safe offline copy. Losing it means asking Google to reset it.
   ```sh
   keytool -genkeypair -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   Use the same password for the store and the key.
3. **Put the key and password in Secret Manager** in the tenant's prod project. Type the password at the prompt; don't write it into a command or a file:
   ```sh
   P=<prod-project-id>
   base64 -w0 upload.jks | gcloud secrets create android-upload-keystore --project=$P --data-file=-
   read -s -p "Upload key password: " PW; printf %s "$PW" | gcloud secrets create android-upload-keystore-password --project=$P --data-file=-; unset PW
   ```
4. **Create the service account Play uses:**
   1. In the prod project's IAM, create a service account (e.g. `play-release`). In the Play Console, under **Users and permissions**, invite its email with the **Release to testing tracks** and **Edit store listing** permissions, for this app only.
   2. Make a JSON key for the service account and store it straight into Secret Manager:
      ```sh
      gcloud iam service-accounts keys create /dev/stdout --iam-account=play-release@$P.iam.gserviceaccount.com \
        | gcloud secrets create play-service-account --project=$P --data-file=-
      ```
   3. Give your own account `roles/secretmanager.secretAccessor` on those three secrets.
5. **First release:**
   1. Play won't take a completed release for an app that has never been published, so run `release <id> --status=draft` the first time, then roll it out in the Console.
   2. Fill in the Play Console's App content forms: privacy policy URL (`https://<share domain>/privacy`), data safety, ads and target audience.
6. **App Links:** once Play App Signing is on, copy its SHA-256 certificate fingerprint into `apps.androidCertSha256` in the tenant file and deploy the share pages. Links then open the installed store app.

## How the signing works

- `tenant flavors` writes `android/app/tenant-flavors.gradle.kts`. When the `UPLOAD_KEYSTORE` environment variable is set, it adds an `upload` signing config.
- `tenant flavors` also patches the template's release build so it uses `upload` when that config exists, and the debug key otherwise. Phone-test APKs stay debug-signed.
- `tenant release` reads the three secrets into a temporary folder that only you can read. It passes the keystore path and password to Gradle as environment variables and deletes the folder when it ends.
- The manual **Phone test APKs** workflow builds one App Bundle with a key and password it generates and throws away. It checks the bundle is signed with that key, so the signing path is tested without any real secret.
