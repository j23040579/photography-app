import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/models.dart';
import 'app_store.dart';

/// System pickers provide access only to files the user explicitly chooses.
class MediaService {
  MediaService(this.store, {ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final AppStore store;
  final ImagePicker _picker;
  bool get canTakePhoto => Platform.isAndroid;
  String? recoveryNotice;

  Future<Memory?> importPhoto(String albumId, {String? promptId}) =>
      _import(albumId, isVideo: false, promptId: promptId);

  Future<Memory?> importVideo(String albumId, {String? promptId}) =>
      _import(albumId, isVideo: true, promptId: promptId);

  Future<Memory?> _import(
    String albumId, {
    required bool isVideo,
    String? promptId,
  }) async {
    final result = await FilePicker.pickFile(
      dialogTitle: isVideo ? 'Add a video memory' : 'Add a photo memory',
      type: FileType.custom,
      allowedExtensions: isVideo
          ? ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm']
          : ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
    );
    if (result == null) return null;
    final path = result.path;
    if (path == null) {
      throw const FileSystemException('This file could not be opened.');
    }
    return store.addMemory(
      albumId,
      File(path),
      isVideo: isVideo,
      promptId: promptId,
    );
  }

  /// Android's system camera can kill/restart the app under memory pressure.
  /// Save the destination first so retrieveLostData can restore that capture.
  Future<Memory?> takePhoto(String albumId, {String? promptId}) async {
    if (!canTakePhoto) {
      throw UnsupportedError('Use the desktop camera or import a photo.');
    }
    final pending = await _pendingFile();
    await pending.writeAsString(
      jsonEncode({'albumId': albumId, 'promptId': promptId}),
      flush: true,
    );
    try {
      final photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) return null;
      return await store.addMemory(
        albumId,
        File(photo.path),
        isVideo: false,
        promptId: promptId,
      );
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  Future<int> recoverLostCapture() async {
    try {
      recoveryNotice = null;
      return await _recoverLostCapture();
    } catch (_) {
      recoveryNotice =
          'An interrupted camera capture could not be restored. '
          'Try importing the photo from your gallery.';
      return 0;
    }
  }

  Future<int> _recoverLostCapture() async {
    if (!Platform.isAndroid) return 0;
    final response = await _picker.retrieveLostData();
    final pending = await _pendingFile();
    if (response.isEmpty) {
      if (await pending.exists()) await pending.delete();
      return 0;
    }
    if (response.exception != null) throw response.exception!;
    if (!await pending.exists()) return 0;
    final context =
        jsonDecode(await pending.readAsString()) as Map<String, dynamic>;
    final albumId = context['albumId'] as String;
    if (!store.albums.any((album) => album.id == albumId)) {
      await pending.delete();
      return 0;
    }
    var count = 0;
    for (final file in response.files ?? <XFile>[]) {
      await store.addMemory(
        albumId,
        File(file.path),
        isVideo: response.type == RetrieveType.video,
        promptId: context['promptId'] as String?,
      );
      count++;
    }
    await pending.delete();
    return count;
  }

  Future<File> _pendingFile() async =>
      File('${(await store.directory).path}/pending_capture.json');
}
