# Google Drive backup and account switching

Click the Google Drive icon and choose **Change Google Drive account**, then **Choose account**. Google opens its account chooser in the browser. After a successful sign-in, turn backup on and choose a save location for the selected account.

Account changes pause backup and wait for an upload already in flight before replacing credentials. Folder IDs, file IDs, upload history, and the old last-backup timestamp are reset for the new account. Local albums and files already in either Drive account are preserved. Cancelling Google's sign-in restores the previous backup destination and enabled preference. Closing only the browser window without completing Google's flow may leave the sign-in pending; Google's cancellation callback is needed to finish it.

OAuth publishing can remain **In production**. Account switching requests `select_account consent`; it does not change publishing status or increase the configured scopes. The default `drive.file` scope only lists folders/files this app created. The existing optional `DRIVE_FULL_ACCESS` build flag still requires suitable Google authorization/verification; production publishing alone is not evidence of scope approval.

## Private build configuration

Do not commit `drive_keys.json`, refresh tokens, signing keys, or actual OAuth values. Client values are compiled into installed apps by this existing desktop OAuth design; installed-app credentials should not be treated as a server-side secret.

For local development use a private JSON file containing the `DRIVE_CLIENT_ID` and `DRIVE_CLIENT_SECRET` fields, and pass its path with `--dart-define-from-file`. Keep the file outside the checkout or in the ignored `drive_keys.json` path.

For cloud builds configure **Settings → Secrets and variables → Actions → Repository secrets**:

- `DRIVE_CLIENT_ID`
- `DRIVE_CLIENT_SECRET`

The workflow reads those secrets into an ignored file during each build and passes it to Flutter. No values are logged or committed. Builds stop with a clear error if either secret is absent, instead of shipping a disabled Drive feature.

Unit tests cover account-selection parameters, cancellation, reset of cross-account backup targets, and waiting for in-flight uploads. Real Google consent and uploads require an interactive device check; automated tests use fake accounts/storage and do not access personal Drive files.

## Google reports `401 invalid_client`

"The OAuth client was not found" means Google did not recognize the client identifier sent by the build. In Google Cloud Console, open **Google Auth Platform → Clients** and confirm the intended **Desktop app** client still exists. Use its OAuth **Client ID**, not the project ID or client secret. Update the two GitHub Actions secrets from the same client, then rerun the cloud build and install the newly generated application. Changing repository secrets cannot update binaries already downloaded.

Build validation rejects malformed client IDs, trims accidental edge whitespace, safely extracts secret values from quotes or recognized Google credential JSON, rejects credential documents for a different client, and prints only a short SHA-256 Client ID fingerprint for comparing configurations. A syntactically valid identifier can still refer to a deleted or incorrect Google client; build validation does not prove registration or consent approval. Publishing status **In production** does not create or repair OAuth clients.
