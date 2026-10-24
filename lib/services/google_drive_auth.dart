import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'drive_backup_engine.dart';
import 'drive_config.dart';

/// Google sign-in for the backup using the browser loopback flow.
/// Real-device OAuth behavior requires validation with the configured client.
///
/// By default only the `drive.file` scope is requested: the app can see only
/// files and folders it created itself, never the rest of the user's Drive.
/// Building with `DRIVE_FULL_ACCESS=true` requests the full `drive` scope so
/// the folder picker can browse every folder (see drive_config.dart).
class GoogleDriveAuth {
  GoogleDriveAuth({required this.root});

  /// The app's private data directory.
  final Directory root;

  static const scopes = driveFullAccess
      ? [drive.DriveApi.driveScope]
      : [drive.DriveApi.driveFileScope];

  /// Saved next to the refresh token, so a token that was granted for the
  /// other scope is never reused (the user is simply asked to sign in again).
  static const _scopeKey = driveFullAccess ? 'full' : 'file';

  bool get configured =>
      driveClientId.isNotEmpty && driveClientSecret.isNotEmpty;

  auth.ClientId get _clientId =>
      auth.ClientId(driveClientId, driveClientSecret);

  File get _file => File('${root.path}/drive_auth.json');

  http.Client? _base;
  auth.AutoRefreshingAuthClient? _client;

  Future<bool> hasSignedIn() async => (await _savedRefreshToken()) != null;

  /// The saved refresh token, or null when there is none or it was granted
  /// for a different scope than this build uses.
  Future<String?> _savedRefreshToken() async {
    try {
      if (!await _file.exists()) return null;
      final saved =
          jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
      // Files written before this field existed used the narrow scope.
      final scope = saved['scope'] as String? ?? 'file';
      if (scope != _scopeKey) return null;
      final refresh = saved['refreshToken'] as String?;
      return refresh == null || refresh.isEmpty ? null : refresh;
    } catch (_) {
      return null;
    }
  }

  /// An authenticated HTTP client. Throws [DriveAuthException] when the user
  /// needs to sign in.
  Future<http.Client> client() async {
    final existing = _client;
    if (existing != null) return existing;
    if (!configured) {
      throw const DriveAuthException(
        'Google Drive backup is not set up in this build.',
      );
    }
    final refresh = await _savedRefreshToken();
    if (refresh == null) throw const DriveAuthException();
    // An already-expired access token makes the client fetch a fresh one.
    final credentials = auth.AccessCredentials(
      auth.AccessToken('Bearer', 'expired', DateTime.utc(2000)),
      refresh,
      scopes,
    );
    final base = http.Client();
    _base = base;
    final created = auth.autoRefreshingClient(_clientId, credentials, base);
    _client = created;
    return created;
  }

  /// Opens Google's consent page in the browser and waits for the result.
  /// Needs internet. Throws if the user cancels.
  Future<void> signIn({bool forceAccountSelection = false}) async {
    if (!configured) {
      throw const DriveAuthException(
        'Google Drive backup is not set up in this build.',
      );
    }
    _closeClients();
    final base = http.Client();
    try {
      final signedIn = await auth.clientViaUserConsent(_clientId, scopes, (
        url,
      ) {
        unawaited(
          launchUrl(
            authorizationUrl(
              Uri.parse(url),
              forceAccountSelection: forceAccountSelection,
            ),
            mode: LaunchMode.externalApplication,
          ),
        );
      }, baseClient: base);
      final refresh = signedIn.credentials.refreshToken;
      if (refresh == null || refresh.isEmpty) {
        signedIn.close();
        throw const DriveAuthException(
          'Google did not allow ongoing access. Remove "Jett\'s Archive" at '
          'myaccount.google.com/permissions and sign in again.',
        );
      }
      final pending = File('${_file.path}.pending');
      await pending.writeAsString(
        jsonEncode({'refreshToken': refresh, 'scope': _scopeKey}),
        flush: true,
      );
      // Windows cannot rename over an existing file. Retain the previous
      // generation until replacement is safely committed.
      final backup = File('${_file.path}.backup');
      if (await _file.exists()) await _file.copy(backup.path);
      try {
        if (Platform.isWindows && await _file.exists()) await _file.delete();
        await pending.rename(_file.path);
      } catch (_) {
        if (await backup.exists()) await backup.copy(_file.path);
        signedIn.close();
        rethrow;
      }
      // Cleanup must not turn a committed credential change into a failure.
      try {
        if (await backup.exists()) await backup.delete();
      } catch (_) {}
      _base = base;
      _client = signedIn;
    } catch (_) {
      base.close();
      rethrow;
    }
  }

  /// Preserve OAuth state/redirect/PKCE parameters while explicitly asking
  /// Google to show its account chooser and grant ongoing backup access.
  static Uri authorizationUrl(
    Uri original, {
    required bool forceAccountSelection,
  }) {
    if (!forceAccountSelection) return original;
    return original.replace(
      queryParameters: {
        ...original.queryParameters,
        'prompt': 'select_account consent',
      },
    );
  }

  Future<void> signOut() async {
    _closeClients();
    if (await _file.exists()) await _file.delete();
  }

  void _closeClients() {
    _client?.close();
    _base?.close();
    _client = null;
    _base = null;
  }
}
