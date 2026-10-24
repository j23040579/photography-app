import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photograph/services/drive_backup_engine.dart';

class FakeDrive implements DriveStorage {
  final calls = <String>[];
  Object? failWith;
  int failAfterCreates = 0; // creates allowed before failWith is thrown
  int _creates = 0;

  @override
  Future<String> ensureFolder(String name, {String? parentId}) async {
    calls.add('folder:$name');
    return 'folder-$name';
  }

  @override
  Future<String> create({
    required String name,
    required String parentId,
    required File file,
    required String mimeType,
  }) async {
    if (failWith != null && _creates >= failAfterCreates) throw failWith!;
    _creates++;
    calls.add('create:$name');
    return 'id-$name';
  }

  @override
  Future<void> replace({
    required String fileId,
    required File file,
    required String mimeType,
  }) async {
    calls.add('replace:$fileId');
  }
}

void main() {
  late Directory root;
  late FakeDrive drive;
  late DriveBackupEngine engine;
  var online = true;

  Future<void> setUpEngine() async {
    root = await Directory.systemTemp.createTemp('backup_test');
    await Directory('${root.path}/media').create();
    await File('${root.path}/media/1-0.jpg').writeAsString('a');
    await File('${root.path}/media/1-1.mp4').writeAsString('b');
    // A half-copied import and an unrelated file must never be uploaded.
    await File('${root.path}/media/1-2.jpg.pending').writeAsString('c');
    await File('${root.path}/media/notes.txt').writeAsString('d');
    await File(
      '${root.path}/photograph.json',
    ).writeAsString(jsonEncode({'v': 1}));
    drive = FakeDrive();
    online = true;
    engine = DriveBackupEngine(
      root: root,
      storage: drive,
      isOnline: () async => online,
      debounce: Duration.zero,
    );
    await engine.load();
  }

  Future<void> tearDownEngine() async {
    engine.dispose();
    await root.delete(recursive: true);
  }

  test('does nothing while disabled', () async {
    await setUpEngine();
    await engine.syncNow();
    expect(drive.calls, isEmpty);
    expect(engine.status.phase, equals(BackupPhase.off));
    await tearDownEngine();
  });

  test('does nothing at all while offline', () async {
    await setUpEngine();
    online = false;
    await engine.setEnabled(true);
    await engine.syncNow();
    expect(drive.calls, isEmpty);
    expect(engine.status.phase, equals(BackupPhase.waitingForInternet));
    await tearDownEngine();
  });

  test('uploads media first, journal last, and only real media', () async {
    await setUpEngine();
    await engine.setEnabled(true);
    await engine.syncNow();
    expect(
      drive.calls,
      equals([
        "folder:Jett's Archive backup",
        'folder:media',
        'create:1-0.jpg',
        'create:1-1.mp4',
        'create:journal.json',
      ]),
    );
    expect(engine.status.phase, equals(BackupPhase.idle));
    expect(engine.status.lastBackup == null, isFalse);
    await tearDownEngine();
  });

  test('a second run with no changes uploads nothing', () async {
    await setUpEngine();
    await engine.setEnabled(true);
    await engine.syncNow();
    drive.calls.clear();
    await engine.syncNow();
    expect(drive.calls, isEmpty);
    await tearDownEngine();
  });

  test(
    'new photo uploads once; edited journal replaces, not duplicates',
    () async {
      await setUpEngine();
      await engine.setEnabled(true);
      await engine.syncNow();
      drive.calls.clear();
      await File('${root.path}/media/2-0.png').writeAsString('new');
      await File(
        '${root.path}/photograph.json',
      ).writeAsString(jsonEncode({'v': 1, 'edited': true}));
      await engine.syncNow();
      expect(
        drive.calls,
        equals(['create:2-0.png', 'replace:id-journal.json']),
      );
      await tearDownEngine();
    },
  );

  test(
    'losing internet mid-backup keeps progress and skips the journal',
    () async {
      await setUpEngine();
      await engine.setEnabled(true);
      drive.failWith = const DriveOfflineException();
      drive.failAfterCreates = 1;
      await engine.syncNow();
      expect(drive.calls.contains('create:1-0.jpg'), isTrue);
      expect(drive.calls.contains('create:1-1.mp4'), isFalse);
      expect(drive.calls.contains('create:journal.json'), isFalse);
      expect(engine.status.phase, equals(BackupPhase.waitingForInternet));

      // Back online: only the remaining file and the journal go up.
      drive.failWith = null;
      drive.calls.clear();
      await engine.syncNow();
      expect(drive.calls, equals(['create:1-1.mp4', 'create:journal.json']));
      expect(engine.status.phase, equals(BackupPhase.idle));
      await tearDownEngine();
    },
  );

  test('progress survives an app restart', () async {
    await setUpEngine();
    await engine.setEnabled(true);
    await engine.syncNow();
    engine.dispose();

    final reopened = DriveBackupEngine(
      root: root,
      storage: drive,
      isOnline: () async => true,
      debounce: Duration.zero,
    );
    await reopened.load();
    drive.calls.clear();
    expect(reopened.enabled, isTrue);
    await reopened.syncNow();
    expect(drive.calls, isEmpty);
    reopened.dispose();
    await root.delete(recursive: true);
  });

  test('revoked sign-in is reported, not thrown', () async {
    await setUpEngine();
    await engine.setEnabled(true);
    drive.failWith = const DriveAuthException();
    await engine.syncNow();
    expect(engine.status.phase, equals(BackupPhase.needsSignIn));
    await tearDownEngine();
  });

  test('a readable Drive problem is passed on to the user', () async {
    await setUpEngine();
    await engine.setEnabled(true);
    drive.failWith = const DriveFailure('Your Google Drive is full.');
    await engine.syncNow();
    expect(engine.status.phase, equals(BackupPhase.error));
    expect(engine.status.detail, equals('Your Google Drive is full.'));
    await tearDownEngine();
  });

  test('overlapping requests never upload a file twice', () async {
    await setUpEngine();
    await engine.setEnabled(true);
    await Future.wait([engine.syncNow(), engine.syncNow(), engine.syncNow()]);
    final photoUploads = drive.calls.where((c) => c == 'create:1-0.jpg');
    expect(photoUploads.length, equals(1));
    await tearDownEngine();
  });

  test('mime types', () {
    expect(DriveBackupEngine.mimeTypeFor('x.JPG'), equals('image/jpeg'));
    expect(DriveBackupEngine.mimeTypeFor('x.mp4'), equals('video/mp4'));
    expect(
      DriveBackupEngine.mimeTypeFor('x.bin'),
      equals('application/octet-stream'),
    );
  });
}
