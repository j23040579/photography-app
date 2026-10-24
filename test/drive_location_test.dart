import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photograph/services/drive_backup_engine.dart';

/// Records every call so tests can see where files were sent.
class _FakeStorage implements DriveStorage {
  final calls = <String>[];
  int _n = 0;

  int count(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  @override
  Future<String> ensureFolder(String name, {String? parentId}) async {
    calls.add('folder:$name@${parentId ?? 'top'}');
    return 'folder${++_n}';
  }

  @override
  Future<String> create({
    required String name,
    required String parentId,
    required File file,
    required String mimeType,
  }) async {
    calls.add('create:$name@$parentId');
    return 'file${++_n}';
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

Future<void> _waitFor(bool Function() done) async {
  final stop = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(stop)) fail('Timed out waiting for the backup.');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory root;
  late _FakeStorage storage;
  late DriveBackupEngine engine;

  DriveBackupEngine makeEngine() => DriveBackupEngine(
    root: root,
    storage: storage,
    isOnline: () async => true,
    debounce: Duration.zero,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('drive_location_test');
    Directory('${root.path}/media').createSync();
    File('${root.path}/media/1-2.jpg').writeAsStringSync('photo');
    File('${root.path}/photograph.json').writeAsStringSync('{}');
    storage = _FakeStorage();
    engine = makeEngine();
  });

  tearDown(() {
    engine.dispose();
    root.deleteSync(recursive: true);
  });

  test('without a choice the default folder is created at the top', () async {
    await engine.load();
    expect(engine.hasLocation, isFalse);
    await engine.setEnabled(true);
    await _waitFor(() => storage.count('create:journal.json') == 1);
    expect(storage.calls, contains("folder:Jett's Archive backup@top"));
    expect(engine.locationLabel, "My Drive › Jett's Archive backup");
  });

  test('a chosen folder is used directly, with no default folder', () async {
    await engine.load();
    await engine.setLocation(folderId: 'chosen', label: 'My Drive › Trips');
    expect(engine.hasLocation, isTrue);
    await engine.setEnabled(true);
    await _waitFor(() => storage.count('create:journal.json') == 1);
    expect(storage.calls, contains('folder:media@chosen'));
    expect(storage.calls, contains('create:journal.json@chosen'));
    expect(storage.calls.where((c) => c.endsWith('@top')), isEmpty);
  });

  test('moving to another folder copies everything there again', () async {
    await engine.load();
    await engine.setLocation(folderId: 'a', label: 'My Drive › A');
    await engine.setEnabled(true);
    await _waitFor(() => storage.count('create:journal.json') == 1);

    await engine.setLocation(folderId: 'b', label: 'My Drive › B');
    await _waitFor(() => storage.count('create:journal.json') == 2);

    expect(storage.calls, contains('folder:media@b'));
    expect(storage.calls, contains('create:journal.json@b'));
    expect(storage.count('create:1-2.jpg'), 2); // once per folder
  });

  test('choosing the same place again does not re-upload anything', () async {
    await engine.load();
    await engine.setLocation(folderId: 'a', label: 'My Drive › A');
    await engine.setEnabled(true);
    await _waitFor(() => storage.count('create:journal.json') == 1);
    final before = storage.calls.length;

    await engine.setLocation(folderId: 'a', label: 'My Drive › A (renamed)');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(storage.calls.length, before);
    expect(engine.locationLabel, 'My Drive › A (renamed)');
  });

  test('the chosen location survives an app restart', () async {
    await engine.load();
    await engine.setLocation(folderId: 'a', label: 'My Drive › A');
    engine.dispose();

    engine = makeEngine();
    await engine.load();
    expect(engine.hasLocation, isTrue);
    expect(engine.locationLabel, 'My Drive › A');
  });
}
