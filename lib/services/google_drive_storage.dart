import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import 'drive_backup_engine.dart';
import 'drive_folders.dart';
import 'google_drive_auth.dart';

/// [DriveStorage] backed by the real Google Drive API. It also lets the UI
/// browse folders so the user can choose where the backup is saved.
class GoogleDriveStorage implements DriveStorage, DriveFolderBrowser {
  GoogleDriveStorage(this._auth);

  final GoogleDriveAuth _auth;

  static const _folderMime = 'application/vnd.google-apps.folder';

  /// Runs [body] and turns Google/network errors into the engine's own
  /// exception types.
  Future<T> _run<T>(Future<T> Function(drive.DriveApi api) body) async {
    try {
      final api = drive.DriveApi(await _auth.client());
      return await body(api);
    } on auth.AccessDeniedException {
      throw const DriveAuthException();
    } on drive.DetailedApiRequestError catch (e) {
      final status = e.status ?? 0;
      final message = (e.message ?? '').toLowerCase();
      if (status == 401) throw const DriveAuthException();
      if (status == 403 && message.contains('quota')) {
        throw const DriveFailure('Your Google Drive is full.');
      }
      if (status == 429 ||
          status >= 500 ||
          (status == 403 && message.contains('rate'))) {
        throw const DriveOfflineException('Google Drive is busy right now.');
      }
      rethrow;
    } on http.ClientException {
      throw const DriveOfflineException();
    }
  }

  static String _quote(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  @override
  Future<String> ensureFolder(String name, {String? parentId}) => _run((
    api,
  ) async {
    final parent = parentId ?? 'root';
    final found = await api.files.list(
      q:
          "name = '${_quote(name)}' and mimeType = '$_folderMime' "
          "and '$parent' in parents and trashed = false",
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id)',
    );
    final existing = found.files;
    if (existing != null && existing.isNotEmpty && existing.first.id != null) {
      return existing.first.id!;
    }
    final created = await api.files.create(
      drive.File(
        name: name,
        mimeType: _folderMime,
        parents: parentId == null ? null : [parentId],
      ),
      $fields: 'id',
    );
    return created.id!;
  });

  @override
  Future<String> create({
    required String name,
    required String parentId,
    required File file,
    required String mimeType,
  }) => _run((api) async {
    final length = await file.length();
    // If an earlier attempt uploaded this file but the answer was lost (or the
    // local backup record was lost), reuse it instead of creating a duplicate.
    final found = await api.files.list(
      q:
          "name = '${_quote(name)}' and '$parentId' in parents "
          'and trashed = false',
      spaces: 'drive',
      pageSize: 1,
      $fields: 'files(id,size)',
    );
    final existing = found.files;
    if (existing != null && existing.isNotEmpty && existing.first.id != null) {
      final match = existing.first;
      final sameSize =
          match.size != null && int.tryParse(match.size!) == length;
      // Photos and videos never change, so a same-size copy is the same file.
      // The journal always changes, so it is always re-uploaded.
      if (sameSize && mimeType != 'application/json') return match.id!;
      await api.files.update(
        drive.File(),
        match.id!,
        uploadMedia: drive.Media(
          file.openRead(),
          length,
          contentType: mimeType,
        ),
        uploadOptions: drive.ResumableUploadOptions(),
      );
      return match.id!;
    }
    final created = await api.files.create(
      drive.File(name: name, parents: [parentId]),
      uploadMedia: drive.Media(file.openRead(), length, contentType: mimeType),
      uploadOptions: drive.ResumableUploadOptions(),
      $fields: 'id',
    );
    return created.id!;
  });

  @override
  Future<void> replace({
    required String fileId,
    required File file,
    required String mimeType,
  }) => _run((api) async {
    final length = await file.length();
    await api.files.update(
      drive.File(),
      fileId,
      uploadMedia: drive.Media(file.openRead(), length, contentType: mimeType),
      uploadOptions: drive.ResumableUploadOptions(),
    );
  });

  @override
  Future<List<DriveFolder>> listFolders({String? parentId}) => _run((
    api,
  ) async {
    final parent = parentId ?? DriveFolder.rootId;
    final folders = <DriveFolder>[];
    String? pageToken;
    do {
      final page = await api.files.list(
        q:
            "mimeType = '$_folderMime' and '${_quote(parent)}' in parents "
            'and trashed = false',
        spaces: 'drive',
        orderBy: 'name',
        pageSize: 100,
        pageToken: pageToken,
        $fields: 'nextPageToken,files(id,name)',
      );
      for (final file in page.files ?? const <drive.File>[]) {
        final id = file.id;
        if (id == null) continue;
        folders.add(DriveFolder(id: id, name: file.name ?? 'Untitled folder'));
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return folders;
  });

  @override
  Future<DriveFolder> createFolder(String name, {String? parentId}) async {
    final id = await ensureFolder(name, parentId: parentId);
    return DriveFolder(id: id, name: name);
  }
}
