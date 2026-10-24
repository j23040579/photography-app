import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the backup needs from Google Drive. Kept tiny so tests can fake it.
abstract class DriveStorage {
  /// Id of the folder called [name] inside [parentId] (or at the top level
  /// when null). Creates it when missing.
  Future<String> ensureFolder(String name, {String? parentId});

  /// Uploads [file] as a new Drive file and returns the new file's id.
  Future<String> create({
    required String name,
    required String parentId,
    required File file,
    required String mimeType,
  });

  /// Replaces the content of an existing Drive file.
  Future<void> replace({
    required String fileId,
    required File file,
    required String mimeType,
  });
}

/// The user must sign in to Google again (token revoked, expired or missing).
class DriveAuthException implements Exception {
  const DriveAuthException([this.message = 'Sign in to Google Drive again.']);
  final String message;
  @override
  String toString() => message;
}

/// The request failed because there is no usable internet connection.
class DriveOfflineException implements Exception {
  const DriveOfflineException([this.message = 'No internet connection.']);
  final String message;
  @override
  String toString() => message;
}

/// A problem the user can understand (for example, "Your Google Drive is
/// full."). Its message is shown as-is.
class DriveFailure implements Exception {
  const DriveFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

enum BackupPhase { off, idle, syncing, waitingForInternet, needsSignIn, error }

class BackupStatus {
  const BackupStatus(this.phase, {this.lastBackup, this.detail});
  final BackupPhase phase;
  final DateTime? lastBackup;
  final String? detail;
}

/// Copies the journal and its media to Google Drive whenever the device is
/// online, and quietly does nothing while it is not.
///
/// * Media files are immutable (their names contain a unique id), so each is
///   uploaded once and remembered in `drive_backup.json`.
/// * The journal file is uploaded last, so the backup never refers to a photo
///   that is not in Drive yet.
/// * Files deleted in the app are NOT deleted from Drive.
/// * Progress is saved after every file, so an interrupted run resumes.
class DriveBackupEngine {
  DriveBackupEngine({
    required this.root,
    required this.storage,
    required this.isOnline,
    DateTime Function()? now,
    this.debounce = const Duration(seconds: 20),
  }) : _now = now ?? DateTime.now;

  /// The app's data directory (contains photograph.json and media/).
  final Directory root;
  final DriveStorage storage;
  final Future<bool> Function() isOnline;
  final Duration debounce;
  final DateTime Function() _now;

  static const folderName = "Jett's Archive backup";
  static final _mediaName = RegExp(r'^\d+-\d+\.[a-z0-9]{1,8}$');

  final _statusController = StreamController<BackupStatus>.broadcast();
  BackupStatus _status = const BackupStatus(BackupPhase.off);
  Timer? _timer;
  bool _running = false;
  Completer<void>? _syncFinished;
  bool _again = false;
  bool _disposed = false;
  Future<void> _pendingSave = Future.value();

  bool _enabled = false;
  String? _folderId;
  String? _locationLabel;
  bool _customLocation = false;
  int _generation = 0; // bumps whenever the save location changes
  String? _mediaFolderId;
  String? _journalFileId;
  String? _journalMarker;
  DateTime? _lastBackup;
  final Map<String, String> _uploaded = {};

  bool get enabled => _enabled;

  /// Where the backup is saved, for display, e.g. `My Drive › Family › Jett`.
  String get locationLabel => _locationLabel ?? 'My Drive › $folderName';

  /// True once the user has picked a location or a first backup has created
  /// the default folder.
  bool get hasLocation => _folderId != null || _locationLabel != null;
  BackupStatus get status => _status;
  Stream<BackupStatus> get statuses => _statusController.stream;

  File get _stateFile => File('${root.path}/drive_backup.json');
  File get _journal => File('${root.path}/photograph.json');

  Future<void> load() async {
    try {
      if (await _stateFile.exists()) {
        final json =
            jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
        _enabled = json['enabled'] as bool? ?? false;
        _folderId = json['folderId'] as String?;
        _locationLabel = json['locationLabel'] as String?;
        _customLocation = json['customLocation'] as bool? ?? false;
        _mediaFolderId = json['mediaFolderId'] as String?;
        _journalFileId = json['journalFileId'] as String?;
        _journalMarker = json['journalMarker'] as String?;
        final last = json['lastBackup'] as String?;
        _lastBackup = last == null ? null : DateTime.tryParse(last);
        _uploaded
          ..clear()
          ..addAll(
            Map<String, String>.from(json['uploaded'] as Map? ?? const {}),
          );
      }
    } catch (_) {
      // A damaged state file only means files may be uploaded again.
    }
    _emit(_enabled ? BackupPhase.idle : BackupPhase.off);
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _save();
    if (value) {
      _emit(BackupPhase.idle);
      requestSync(immediate: true);
    } else {
      _timer?.cancel();
      _emit(BackupPhase.off);
    }
  }

  /// Chooses where the backup is saved.
  ///
  /// [folderId] null means the default folder ("Jett's Archive backup" at the
  /// top of My Drive). Otherwise the journal and a `media` folder are written
  /// straight into that folder.
  ///
  /// Moving to a different folder starts a fresh backup there (everything is
  /// copied again). Copies already in the old folder are left untouched.
  Future<void> setLocation({String? folderId, required String label}) async {
    final unchanged = folderId == null
        ? !_customLocation // default -> default
        : _customLocation && folderId == _folderId; // same custom folder
    if (unchanged) {
      _locationLabel = label;
      await _save();
      _emit(_status.phase);
      return;
    }
    _generation++; // a run already in progress must not record its results
    _timer?.cancel();
    _customLocation = folderId != null;
    _folderId = folderId;
    _locationLabel = label;
    _mediaFolderId = null;
    _journalFileId = null;
    _journalMarker = null;
    _uploaded.clear();
    await _save();
    if (_enabled) {
      _emit(BackupPhase.idle);
      requestSync(immediate: true);
    } else {
      _emit(BackupPhase.off);
    }
  }

  /// Ask for a backup. Many rapid requests (one per edit) become one run.
  void requestSync({bool immediate = false}) {
    if (!_enabled || _disposed) return;
    _timer?.cancel();
    _timer = Timer(immediate ? Duration.zero : debounce, () {
      unawaited(syncNow());
    });
  }

  /// Runs one backup now. Never throws; problems become [status].
  Future<void> syncNow() async {
    if (!_enabled || _disposed) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    _syncFinished = Completer<void>();
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again && _enabled && !_disposed);
    } finally {
      _running = false;
      _syncFinished?.complete();
      _syncFinished = null;
    }
  }

  Future<bool> _online() async {
    try {
      return await isOnline();
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncOnce() async {
    final generation = _generation;
    // Offline: do nothing at all. The next connectivity change retries.
    if (!await _online()) {
      _emit(BackupPhase.waitingForInternet);
      return;
    }
    if (!_enabled || _disposed || generation != _generation) return;
    _emit(BackupPhase.syncing);
    // If the save location changes while this run is in progress, the run
    // stops quietly and the next one starts fresh in the new place.
    bool moved() => generation != _generation || !_enabled || _disposed;
    try {
      var folderId = _folderId;
      if (folderId == null) {
        folderId = await storage.ensureFolder(folderName);
        if (moved()) return;
        _folderId = folderId;
      }
      var mediaFolderId = _mediaFolderId;
      if (mediaFolderId == null) {
        mediaFolderId = await storage.ensureFolder('media', parentId: folderId);
        if (moved()) return;
        _mediaFolderId = mediaFolderId;
      }
      await _save();

      for (final file in await _pendingMedia()) {
        if (!_enabled || _disposed || moved()) return;
        if (!await _online()) {
          _emit(BackupPhase.waitingForInternet);
          return;
        }
        final name = _basename(file.path);
        if (!await file.exists()) continue; // removed while syncing
        final id = await storage.create(
          name: name,
          parentId: mediaFolderId,
          file: file,
          mimeType: mimeTypeFor(name),
        );
        if (moved()) return;
        _uploaded[name] = id;
        await _save();
      }

      if (moved()) return;
      await _syncJournal(folderId, moved);
      if (moved()) return;
      _lastBackup = _now();
      await _save();
      _emit(BackupPhase.idle);
    } on DriveAuthException catch (e) {
      _emit(BackupPhase.needsSignIn, detail: e.message);
    } on DriveFailure catch (e) {
      _emit(BackupPhase.error, detail: e.message);
    } on DriveOfflineException {
      _emit(BackupPhase.waitingForInternet);
    } on SocketException {
      _emit(BackupPhase.waitingForInternet);
    } on TimeoutException {
      _emit(BackupPhase.waitingForInternet);
    } on HandshakeException {
      _emit(BackupPhase.waitingForInternet);
    } catch (_) {
      _emit(
        BackupPhase.error,
        detail: 'The backup could not finish. It will try again later.',
      );
    }
  }

  Future<List<File>> _pendingMedia() async {
    final media = Directory('${root.path}/media');
    if (!await media.exists()) return const [];
    final files = <File>[];
    await for (final entry in media.list(followLinks: false)) {
      if (entry is! File) continue;
      final name = _basename(entry.path);
      if (!_mediaName.hasMatch(name)) continue; // skips *.pending files
      if (_uploaded.containsKey(name)) continue;
      files.add(entry);
    }
    files.sort((a, b) => _basename(a.path).compareTo(_basename(b.path)));
    return files;
  }

  Future<void> _syncJournal(String folderId, bool Function() moved) async {
    if (!await _journal.exists()) return;
    final stat = await _journal.stat();
    final marker = '${stat.modified.millisecondsSinceEpoch}:${stat.size}';
    if (marker == _journalMarker) return;
    // Upload a snapshot so a save in progress cannot be half-read.
    final snapshot = File('${root.path}/photograph.upload.json');
    try {
      await _journal.copy(snapshot.path);
      final knownId = _journalFileId;
      if (knownId == null) {
        final created = await storage.create(
          name: 'journal.json',
          parentId: folderId,
          file: snapshot,
          mimeType: 'application/json',
        );
        if (moved()) return; // it went to the old folder; start over there
        _journalFileId = created;
      } else {
        await storage.replace(
          fileId: knownId,
          file: snapshot,
          mimeType: 'application/json',
        );
        if (moved()) return;
      }
      _journalMarker = marker;
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Map<String, dynamic> _accountState() => {
    'enabled': _enabled,
    'folderId': _folderId,
    'locationLabel': _locationLabel,
    'customLocation': _customLocation,
    'mediaFolderId': _mediaFolderId,
    'journalFileId': _journalFileId,
    'journalMarker': _journalMarker,
    'lastBackup': _lastBackup?.toIso8601String(),
    'uploaded': Map<String, String>.from(_uploaded),
  };

  /// Stop all activity before replacing credentials. Persist a clean account
  /// boundary first, so a crash cannot pair new credentials with old file IDs.
  Future<Map<String, dynamic>> prepareAccountChange() async {
    final wasEnabled = _enabled;
    _enabled = false;
    _generation++;
    _timer?.cancel();
    _again = false;
    await _syncFinished?.future;
    final previous = _accountState()..['enabled'] = wasEnabled;
    _folderId = null;
    _locationLabel = null;
    _customLocation = false;
    _mediaFolderId = null;
    _journalFileId = null;
    _journalMarker = null;
    _lastBackup = null;
    _uploaded.clear();
    await _save();
    _emit(BackupPhase.off);
    return previous;
  }

  /// A cancelled/failed account chooser retains the old credentials and target.
  Future<void> restoreAccountChange(Map<String, dynamic> previous) async {
    _folderId = previous['folderId'] as String?;
    _locationLabel = previous['locationLabel'] as String?;
    _customLocation = previous['customLocation'] as bool;
    _mediaFolderId = previous['mediaFolderId'] as String?;
    _journalFileId = previous['journalFileId'] as String?;
    _journalMarker = previous['journalMarker'] as String?;
    _lastBackup = previous['lastBackup'] == null
        ? null
        : DateTime.parse(previous['lastBackup'] as String);
    _uploaded
      ..clear()
      ..addAll(Map<String, String>.from(previous['uploaded'] as Map));
    await setEnabled(previous['enabled'] as bool);
  }

  Future<void> _save() {
    // An upload and a folder/account change can save concurrently. Queue each
    // snapshot so they cannot rename or overwrite one another's temp file.
    final snapshot = _accountState();
    final operation = _pendingSave.then((_) async {
      final temp = File('${_stateFile.path}.tmp');
      await temp.writeAsString(jsonEncode(snapshot), flush: true);
      if (Platform.isWindows && await _stateFile.exists()) {
        await _stateFile.delete();
      }
      await temp.rename(_stateFile.path);
    });
    _pendingSave = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _emit(BackupPhase phase, {String? detail}) {
    _status = BackupStatus(phase, lastBackup: _lastBackup, detail: detail);
    if (!_statusController.isClosed) _statusController.add(_status);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_statusController.close());
  }

  static String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  static String mimeTypeFor(String name) {
    final dot = name.lastIndexOf('.');
    switch (dot < 0 ? '' : name.substring(dot + 1).toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'mp4':
        return 'video/mp4';
      case 'm4v':
        return 'video/x-m4v';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      default:
        return 'application/octet-stream';
    }
  }
}
