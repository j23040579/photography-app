import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/models.dart';
import '../domain/suggestion_engine.dart';

/// The single source of truth. No account, server, or network is required.
/// A recoverable backup protects the previous committed state during replacement.
class AppStore extends ChangeNotifier {
  AppStore({Directory? directory}) : _directory = directory;

  Directory? _directory;
  List<Album> _albums = [];
  bool _onboardingComplete = false;
  bool _loaded = false;
  Future<void> _writes = Future.value();
  final Set<String> _activeImports = {};
  SuggestionEngine engine = SuggestionEngine();
  String? loadError;
  String? recoveryNotice;

  List<Album> get albums => List.unmodifiable(_albums);
  bool get onboardingComplete => _onboardingComplete;
  bool get loaded => _loaded;

  Future<Directory> get directory async =>
      _directory ??= await getApplicationSupportDirectory();

  Future<void> load() async {
    if (_loaded) return;
    final root = await directory;
    await root.create(recursive: true);
    final current = File('${root.path}/photograph.json');
    final backup = File('${root.path}/photograph.backup.json');
    Map<String, dynamic>? state;
    Object? failure;
    for (final file in [current, backup]) {
      if (!await file.exists()) continue;
      try {
        final candidate =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (candidate['version'] != 1) {
          throw const FormatException('Unsupported local data version.');
        }
        // Validate the entire document before accepting it.
        final albums = (candidate['albums'] as List<dynamic>)
            .map(
              (item) => Album.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
        final learner = SuggestionEngine(
          state: Map<String, dynamic>.from(candidate['model'] as Map? ?? {}),
        );
        _albums = albums;
        engine = learner;
        state = candidate;
        if (file.path == backup.path) {
          recoveryNotice = 'Recovered your library from its last saved backup.';
          if (await current.exists()) {
            await current.copy(
              '${root.path}/photograph.corrupt-${DateTime.now().microsecondsSinceEpoch}.json',
            );
          }
          // Restore the known-good generation before any later mutation can
          // rotate a corrupt current file over the valid backup.
          await backup.copy(current.path);
        }
        break;
      } catch (error) {
        failure = error;
      }
    }
    if (state == null && failure != null) {
      // Do not overwrite corrupt user data with an empty library.
      throw FileSystemException(
        'Your library could not be read. Its files have been preserved.',
        current.path,
      );
    }
    _onboardingComplete = state?['onboardingComplete'] as bool? ?? false;
    _loaded = true;
    notifyListeners();
  }

  /// UI-safe loading. Keep [load] throwing for callers that need to handle the
  /// underlying error; this wrapper provides a retryable app-level error state.
  Future<void> tryLoad() async {
    loadError = null;
    recoveryNotice = null;
    try {
      await load();
    } catch (_) {
      loadError =
          'Your library could not be opened. Your saved files have been '
          'preserved. Check available storage and try again.';
      notifyListeners();
    }
  }

  Album album(String id) => _albums.firstWhere((item) => item.id == id);

  Future<void> finishOnboarding() => _commit(() {
    _onboardingComplete = true;
  });

  Future<Album> createAlbum({
    required String title,
    required PlaceCategory category,
    required DateTime eventDate,
  }) async {
    if (title.trim().isEmpty) throw ArgumentError('Give your album a name.');
    late Album created;
    await _commit(() {
      created = Album(
        id: _id(),
        title: title.trim(),
        category: category,
        eventDate: eventDate,
        createdAt: DateTime.now(),
        prompts: engine.generate(category),
      );
      _albums = [created, ..._albums];
    });
    return created;
  }

  Future<void> saveAlbum(Album updated) => _commit(() {
    if (!_albums.any((item) => item.id == updated.id)) {
      throw StateError('This album no longer exists.');
    }
    if (updated.title.trim().isEmpty) {
      throw ArgumentError('Give your album a name.');
    }
    _albums = _albums
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
  });

  Future<void> deleteAlbum(String id) async {
    album(id);
    await _commit(() {
      _albums = _albums.where((item) => item.id != id).toList();
    });
  }

  Future<void> recordFeedback(PhotoPrompt prompt, bool liked) =>
      _commit(() => engine.feedback(prompt, liked));

  Future<void> replacePrompt(String albumId, String promptId) => _commit(() {
    final old = album(albumId);
    final prompt = old.prompts.firstWhere((item) => item.id == promptId);
    engine.feedback(prompt, false);
    final replacement = engine
        .generate(
          old.category,
          count: 1,
          exclude: old.prompts.map((item) => item.text).toSet(),
        )
        .single;
    // Keep the ID so linked memories and completion remain meaningful.
    final next = replacement.copyWith(
      id: prompt.id,
      completed: prompt.completed,
    );
    _replace(
      old.copyWith(
        prompts: old.prompts
            .map((item) => item.id == promptId ? next : item)
            .toList(),
      ),
    );
  });

  Future<Memory> addMemory(
    String albumId,
    File source, {
    required bool isVideo,
    String? promptId,
  }) async {
    album(albumId);
    final root = await directory;
    final targetDir = Directory('${root.path}/media');
    await targetDir.create(recursive: true);
    final name = source.path.split(RegExp(r'[/\\]')).last;
    final suffix = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final safeSuffix = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(suffix)
        ? '.$suffix'
        : (isVideo ? '.mp4' : '.jpg');
    final memory = Memory(
      id: _id(),
      path: '',
      isVideo: isVideo,
      createdAt: DateTime.now(),
      promptId: promptId,
    );
    final destination = File('${targetDir.path}/${memory.id}$safeSuffix');
    final pending = File('${destination.path}.pending');
    _activeImports.add(destination.absolute.uri.toString());
    try {
      await source.copy(pending.path);
      await pending.rename(destination.path);
      final saved = memory.copyWith(path: destination.path);
      await _commit(() {
        final old = album(albumId);
        _replace(
          old.copyWith(
            memories: [...old.memories, saved],
            prompts: old.prompts.map((prompt) {
              return prompt.id == promptId
                  ? prompt.copyWith(completed: true)
                  : prompt;
            }).toList(),
          ),
        );
      });
      return saved;
    } catch (_) {
      if (await pending.exists()) await pending.delete();
      if (await destination.exists()) await destination.delete();
      rethrow;
    } finally {
      _activeImports.remove(destination.absolute.uri.toString());
    }
  }

  Future<void> removeMemory(String albumId, String memoryId) async {
    album(albumId).memories.firstWhere((m) => m.id == memoryId);
    await _commit(() {
      final old = album(albumId);
      _replace(
        old.copyWith(
          memories: old.memories.where((m) => m.id != memoryId).toList(),
        ),
      );
    });
  }

  Future<void> saveCaption(String albumId, String memoryId, String caption) =>
      _commit(() {
        final old = album(albumId);
        _replace(
          old.copyWith(
            memories: old.memories
                .map((m) => m.id == memoryId ? m.copyWith(caption: caption) : m)
                .toList(),
          ),
        );
      });

  void _replace(Album updated) {
    _albums = _albums.map((a) => a.id == updated.id ? updated : a).toList();
  }

  Map<String, dynamic> _state() => {
    'version': 1,
    'onboardingComplete': _onboardingComplete,
    'albums': _albums.map((album) => album.toJson()).toList(),
    'model': engine.toJson(),
  };

  Future<void> _commit(void Function() action) {
    // Serialise mutations and disk writes so rapid edits cannot lose updates.
    final operation = _writes.then((_) async {
      if (!_loaded) throw StateError('Load your library before editing it.');
      final before = _state();
      try {
        action();
        final root = await directory;
        final current = File('${root.path}/photograph.json');
        final temp = File('${root.path}/photograph.pending.json');
        final backup = File('${root.path}/photograph.backup.json');
        await temp.writeAsString(jsonEncode(_state()), flush: true);
        if (await current.exists()) await current.copy(backup.path);
        // POSIX atomically replaces. Windows cannot rename over an existing
        // file, so retain the backup before removing the previous destination.
        if (Platform.isWindows && await current.exists()) {
          await current.delete();
        }
        await temp.rename(current.path);
        notifyListeners();
        await _collectUnreferencedMedia();
      } catch (_) {
        _albums = (before['albums'] as List<dynamic>)
            .map((item) => Album.fromJson(item as Map<String, dynamic>))
            .toList();
        _onboardingComplete = before['onboardingComplete'] as bool;
        engine = SuggestionEngine(
          state: before['model'] as Map<String, dynamic>,
        );
        rethrow;
      }
    });
    // An individual failure should not poison later writes.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _collectUnreferencedMedia() async {
    try {
      final root = await directory;
      final media = Directory('${root.path}/media');
      if (!await media.exists()) return;
      final retained = <String>{..._activeImports};
      for (final name in ['photograph.json', 'photograph.backup.json']) {
        final file = File('${root.path}/$name');
        if (!await file.exists()) continue;
        final state =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        for (final item in state['albums'] as List<dynamic>) {
          for (final memory in (item as Map)['memories'] as List<dynamic>) {
            final path = (memory as Map)['path'] as String;
            retained.add(File(path).absolute.uri.toString());
          }
        }
      }
      await for (final entry in media.list(followLinks: false)) {
        if (entry is! File) continue;
        final basename = entry.uri.pathSegments.last;
        // Only remove files created by this app. Keep one previous generation's
        // media so the backup remains recoverable after deletion from the UI.
        if (!RegExp(r'^\d+-\d+\.[a-z0-9]{1,8}$').hasMatch(basename)) continue;
        final uri = entry.absolute.uri.toString();
        if (!retained.contains(uri) && !_activeImports.contains(uri)) {
          await entry.delete();
        }
      }
    } on Object {
      // Garbage collection must not turn a committed edit into a failed write.
      // Open Windows viewers or a damaged backup simply defer cleanup.
    }
  }

  static int _sequence = 0;
  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
}
