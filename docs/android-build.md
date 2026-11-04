# Android builds with live Firebase settings (Cloud Shell)

The **Phone test APKs** workflow builds on demo data, because CI never gets Firebase settings. To try something that needs a real project on a phone (sign-in, saved searches, push alerts, M-Pesa), build in Cloud Shell. Cloud Shell has no Android SDK, so `tools/cloudshell-android.sh` installs one first. The same setup serves `tenant release` (`docs/store-release.md`).

Copy the block **as it is**: these are bash commands with `/` paths. The PowerShell commands in the README are for Windows.

```sh
cd ~/realtor-platform && git pull
source tools/cloudshell-android.sh          # about 5 minutes; again in each new Cloud Shell session
(cd tools/tenant-cli && npm ci)
flutter pub get

cd apps/realtor_app
flutter create . --platforms=android --project-name realtor_app >/dev/null
node ../../tools/tenant-cli/src/cli.ts flavors realtime-estates
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create --flavors realtimeEstates
# Cloud Shell has less memory than the template's 8 GB Gradle heap.
sed -i 's/^org.gradle.jvmargs=.*/org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=512m/' android/gradle.properties

node ../../tools/tenant-cli/src/cli.ts firebase-config realtime-estates dev --flavor
flutter build apk --release --flavor realtimeEstates --split-per-abi --target-platform android-arm64
cloudshell download build/app/outputs/flutter-apk/app-arm64-v8a-realtimeestates-release.apk
```

- `firebase-config` needs the firebase CLI signed in (`firebase login --no-localhost`).
- The first build downloads Gradle and its plugins, which takes about 10 minutes. Later builds in the same session are faster.
- The APK is signed with a debug key made on this machine. **Uninstall the phone test app first**: Android refuses an update signed with a different key ("App not installed").
- Swap `realtime-estates` / `realtimeEstates` and `dev` for another tenant or environment. Store builds come from `tenant release`, never from here.

## Sign-in on test builds (once per build machine)

Firebase trusts only the signing certificates it knows. Without them, Google sign-in fails, and emailed links open the browser instead of the app. Gradle makes the key for these builds the first time; in Cloud Shell it lives in `~/.android/debug.keystore` and survives sessions, so this is done once.

1. Print its fingerprints:
   ```sh
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep -E 'SHA1|SHA256'
   ```
2. Add them to the tenant file under `apps.testCerts`. Fingerprints are public, so they can be committed; the keystore never is.
   ```json
   "testCerts": [{ "name": "Cloud Shell debug key", "sha1": "AB:CD:…", "sha256": "12:34:…" }]
   ```
3. Run `tenant deploy <id> dev --only=infra,web`. Terraform registers the certificates on the dev and stage projects, and the app site publishes `/.well-known/assetlinks.json`, so Android opens emailed links in the app.
4. Rebuild from the `flavors` line onwards, so the manifest picks up the email-link filter.

The store build's certificate goes in `apps.androidCertSha256` and `apps.androidCertSha1`, from Play Console → Test and release → App integrity → App signing; prod uses only those. Terraform owns this list, so fingerprints added by hand in the Firebase console are removed at the next infra deploy.

## Checking push alerts (P4-s03)

1. Install the APK and sign in under **Account**, with the email link or Google. Both need the step above. If either fails, the message ends with Firebase's reason in brackets.
2. Search, for example to rent in Kilimani, tap **Get alerts for new matches**, and allow notifications.
3. Leave the app. In the admin, create a listing that matches the search and approve it.
4. Within 5 minutes the phone shows "A new home matches your search". Tapping it opens the home.

If nothing arrives, look at the `savedSearchAlerts` logs in Cloud Logging. Each run logs `alerts: N new listings, N alerts, N pushes`.
