import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'app_store.dart';
import 'drive_backup_engine.dart';
import 'drive_config.dart';
import 'drive_folders.dart';
import 'google_drive_auth.dart';
import 'google_drive_storage.dart';

/// Wires the backup engine to the app: it backs up after edits, when the app
/// starts, and whenever the device comes back online.
class DriveBackupService {
  DriveBackupService._(
    this.engine,
    this._auth,
    this._folders,
    this._subscription,
  );

  /// Dependency-injected construction for hosts and tests without platform plugins.
  DriveBackupService.withDependencies({
    required this.engine,
    required GoogleDriveAuth authentication,
    DriveFolderBrowser? folders,
  }) : _auth = authentication,
       _folders = folders ?? GoogleDriveStorage(authentication),
       _subscription = null;

  bool _changingAccount = false;

  void _checkAccountChange() {
    if (_changingAccount) {
      throw StateError('Finish changing your Google Drive account first.');
    }
  }

  final DriveBackupEngine engine;
  final GoogleDriveAuth _auth;
  final DriveFolderBrowser _folders;
  final StreamSubscription<List<ConnectivityResult>>? _subscription;

  /// False when this build has no Google OAuth client configured.
  bool get available => _auth.configured;
  bool get enabled => engine.enabled;

  /// True when this build can browse the user's whole Drive. Otherwise the
  /// folder picker shows only folders created by this app.
  bool get fullAccess => driveFullAccess;

  /// Where the backup is saved, e.g. `My Drive › Family › Jett`.
  String get locationLabel => engine.locationLabel;

  /// Whether a save location has been chosen (or the default was created).
  bool get hasLocation => engine.hasLocation;
  BackupStatus get status => engine.status;
  Stream<BackupStatus> get statuses => engine.statuses;

  /// Call inside a try/catch: if it fails the app should simply run with no
  /// backup.
  static Future<DriveBackupService> start(AppStore store) async {
    final root = await store.directory;
    final auth = GoogleDriveAuth(root: root);
    final connectivity = Connectivity();

    bool connected(List<ConnectivityResult> results) =>
        results.any((r) => r != ConnectivityResult.none);

    Future<bool> online() async {
      try {
        return connected(await connectivity.checkConnectivity());
      } catch (_) {
        // If the check itself fails, try anyway; a failed request is handled.
        return true;
      }
    }

    final storage = GoogleDriveStorage(auth);
    final engine = DriveBackupEngine(
      root: root,
      storage: storage,
      isOnline: online,
    );
    await engine.load();
    store.addListener(engine.requestSync);

    StreamSubscription<List<ConnectivityResult>>? subscription;
    try {
      subscription = connectivity.onConnectivityChanged.listen((results) {
        if (connected(results)) engine.requestSync(immediate: true);
      });
    } catch (_) {
      subscription = null;
    }
    engine.requestSync(); // catch up shortly after the app opens
    return DriveBackupService._(engine, auth, storage, subscription);
  }

  /// Signs in to Google if needed (needs internet). Does not turn the backup
  /// on, so the user can pick a save location first.
  Future<void> signInIfNeeded() async {
    _checkAccountChange();
    if (!available) {
      throw StateError('Google Drive backup is not set up in this build.');
    }
    if (!await _auth.hasSignedIn()) await _auth.signIn();
  }

  /// Signs in (needs internet) and turns the backup on.
  Future<void> enable() async {
    await signInIfNeeded();
    await engine.setEnabled(true);
  }

  /// Sub-folders of [parentId] (or of My Drive when null) for the picker.
  Future<List<DriveFolder>> listFolders({String? parentId}) async {
    await signInIfNeeded();
    return _folders.listFolders(parentId: parentId);
  }

  /// Finds or creates a folder for the picker.
  Future<DriveFolder> createFolder(String name, {String? parentId}) async {
    await signInIfNeeded();
    return _folders.createFolder(name, parentId: parentId);
  }

  /// Saves future backups in [location]. Moving to a different folder copies
  /// everything there again; copies in the old folder stay where they are.
  Future<void> setLocation(DriveLocation location) {
    _checkAccountChange();
    return engine.setLocation(
      folderId: location.folderId,
      label: location.label,
    );
  }

  /// Turns the backup off. Files already in Drive stay there.
  Future<void> disable() => engine.setEnabled(false);

  /// Signs in again after Google revoked or expired the sign-in.
  Future<void> reconnect() async {
    _checkAccountChange();
    await _auth.signIn();
    engine.requestSync(immediate: true);
  }

  /// Opens Google's account chooser. A successful change leaves backup off
  /// until a destination is selected for the new account.
  Future<void> changeAccount() async {
    if (!available) {
      throw StateError('Google Drive backup is not set up in this build.');
    }
    _checkAccountChange();
    _changingAccount = true;
    try {
      final previous = await engine.prepareAccountChange();
      try {
        await _auth.signIn(forceAccountSelection: true);
      } catch (_) {
        await engine.restoreAccountChange(previous);
        rethrow;
      }
    } finally {
      _changingAccount = false;
    }
  }

  Future<void> backupNow() => engine.syncNow();

  void dispose() {
    unawaited(_subscription?.cancel());
    engine.dispose();
  }
}
