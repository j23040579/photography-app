/// OAuth client created in Google Cloud Console (type: "Desktop app").
/// Pass them at build time so they are not committed to the repository:
///
///   flutter run -d windows \
///     --dart-define=DRIVE_CLIENT_ID=xxxx.apps.googleusercontent.com \
///     --dart-define=DRIVE_CLIENT_SECRET=xxxx
///
/// Without them the app still works; the Drive backup switch just explains
/// that it is not set up.
const driveClientId = String.fromEnvironment('DRIVE_CLIENT_ID');
const driveClientSecret = String.fromEnvironment('DRIVE_CLIENT_SECRET');

/// Optional. By default the app uses the narrow `drive.file` scope, so the
/// folder picker shows only folders this app created (plus any new ones the
/// user makes in the picker). Build with
///
///   --dart-define=DRIVE_FULL_ACCESS=true
///
/// to request the full `drive` scope instead. The picker then shows EVERY
/// folder in the user's Drive. `drive` is a "restricted" scope: it works for
/// the test users of a project in "Testing", but publishing the app to
/// everyone requires Google's verification process.
const driveFullAccess = bool.fromEnvironment('DRIVE_FULL_ACCESS');
