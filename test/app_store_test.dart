import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photograph/domain/models.dart';
import 'package:photograph/services/app_store.dart';
import 'package:photograph/services/reminder_service.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('photograph-test-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<Album> create(AppStore store) => store.createAlbum(
    title: 'Dinner with friends',
    category: PlaceCategory.restaurant,
    eventDate: DateTime(2026, 11, 2),
  );

  test(
    'albums, onboarding, edits and learned preferences survive restart',
    () async {
      final first = AppStore(directory: directory);
      await first.load();
      final album = await create(first);
      await first.finishOnboarding();
      await first.recordFeedback(album.prompts.first, true);
      await first.saveAlbum(
        album.copyWith(notes: 'Try the terrace', rating: 4),
      );

      final reopened = AppStore(directory: directory);
      await reopened.load();
      expect(reopened.onboardingComplete, isTrue);
      expect(reopened.albums.single.notes, 'Try the terrace');
      expect(reopened.albums.single.rating, 4);
      expect(reopened.engine.feedbackCount, 1);
      expect(reopened.albums.single.prompts, hasLength(5));
      expect(reopened.albums.single.category, PlaceCategory.restaurant);
    },
  );

  test('rapid queued creates are all retained on disk', () async {
    final store = AppStore(directory: directory);
    await store.load();
    await Future.wait(List.generate(12, (_) => create(store)));
    final reopened = AppStore(directory: directory);
    await reopened.load();
    expect(reopened.albums, hasLength(12));
    expect(reopened.albums.map((album) => album.id).toSet(), hasLength(12));
  });

  test(
    'memory copying is durable and deletion never removes the source',
    () async {
      final store = AppStore(directory: directory);
      await store.load();
      final album = await create(store);
      final source = File('${directory.path}/original.jpg');
      await source.writeAsBytes([1, 2, 3, 4]);
      final memory = await store.addMemory(
        album.id,
        source,
        isVideo: false,
        promptId: album.prompts.first.id,
      );
      expect(await File(memory.path).readAsBytes(), [1, 2, 3, 4]);
      expect(memory.path, isNot(source.path));
      expect(store.album(album.id).prompts.first.completed, isTrue);
      await store.saveCaption(album.id, memory.id, 'The best table');
      final reopened = AppStore(directory: directory);
      await reopened.load();
      expect(reopened.albums.single.memories.single.caption, 'The best table');
      await reopened.deleteAlbum(album.id);
      expect(await source.exists(), isTrue);
      // The previous saved generation retains its photos for crash recovery.
      expect(await File(memory.path).exists(), isTrue);
      await reopened.finishOnboarding();
      expect(await File(memory.path).exists(), isFalse);
    },
  );

  test('corrupt current library recovers valid previous backup', () async {
    final store = AppStore(directory: directory);
    await store.load();
    final album = await create(store);
    await store.saveAlbum(album.copyWith(notes: 'Last edit'));
    await File('${directory.path}/photograph.json').writeAsString('{ broken');
    final reopened = AppStore(directory: directory);
    await reopened.load();
    expect(reopened.albums.single.id, album.id);
    expect(reopened.loadError, isNull);
    expect(reopened.recoveryNotice, contains('Recovered'));
  });

  test('unreadable data is preserved rather than overwritten', () async {
    final file = File('${directory.path}/photograph.json');
    await file.writeAsString(jsonEncode({'version': 900}));
    final store = AppStore(directory: directory);
    await expectLater(store.load(), throwsA(isA<FileSystemException>()));
    expect(store.loaded, isFalse);
    expect(jsonDecode(await file.readAsString())['version'], 900);
  });

  test('tryLoad exposes a retryable error without throwing', () async {
    final file = File('${directory.path}/photograph.json');
    await file.writeAsString('{ broken');
    final store = AppStore(directory: directory);
    await store.tryLoad();
    expect(store.loaded, isFalse);
    expect(store.loadError, isNotNull);
    await file.delete();
    await store.tryLoad();
    expect(store.loaded, isTrue);
    expect(store.loadError, isNull);
  });

  test('failed mutations roll back and do not poison later writes', () async {
    final store = AppStore(directory: directory);
    await store.load();
    final album = await create(store);
    await expectLater(
      store.saveAlbum(album.copyWith(title: '')),
      throwsArgumentError,
    );
    expect(store.albums.single.title, album.title);
    await store.saveAlbum(album.copyWith(notes: 'Works after failure'));
    expect(store.albums.single.notes, 'Works after failure');
  });

  test('failed disk writes roll back model and data together', () async {
    final store = AppStore(directory: directory);
    await store.load();
    final album = await create(store);
    final blockedPath = Directory('${directory.path}/photograph.pending.json');
    await blockedPath.create();
    await expectLater(
      store.recordFeedback(album.prompts.first, true),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.engine.feedbackCount, 0);
    await blockedPath.delete();
    await store.recordFeedback(album.prompts.first, true);
    expect(store.engine.feedbackCount, 1);
  });

  test('reminder IDs are stable and fit native signed integer range', () {
    expect(
      ReminderService.notificationId('album-123'),
      ReminderService.notificationId('album-123'),
    );
    expect(
      ReminderService.notificationId('album-123'),
      isNot(ReminderService.notificationId('album-124')),
    );
    expect(
      ReminderService.notificationId('album-123'),
      inInclusiveRange(0, 0x7fffffff),
    );
  });
}
