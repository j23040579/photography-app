/// A folder in the user's Google Drive, as shown in the folder picker.
class DriveFolder {
  const DriveFolder({required this.id, required this.name});

  /// Drive's id for the folder. [rootId] stands for "My Drive" itself.
  final String id;
  final String name;

  /// Drive's alias for the top level of "My Drive".
  static const rootId = 'root';

  @override
  bool operator ==(Object other) =>
      other is DriveFolder && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Where the backup should be saved.
///
/// [folderId] is null when the user wants the default folder
/// ("Jett's Archive backup" at the top of My Drive). Otherwise the backup is
/// written straight into that folder.
class DriveLocation {
  const DriveLocation({required this.folderId, required this.label});

  final String? folderId;

  /// Human readable path, for example `My Drive › Family › Jett`.
  final String label;

  bool get isDefault => folderId == null;
}

/// Lets the UI browse and create folders. Kept apart from `DriveStorage` so
/// the backup engine (and its tests) never need to know about browsing.
abstract class DriveFolderBrowser {
  /// Sub-folders of [parentId], or of the top of My Drive when null, sorted
  /// by name.
  Future<List<DriveFolder>> listFolders({String? parentId});

  /// Finds or creates a folder called [name] inside [parentId] (or at the top
  /// of My Drive when null).
  Future<DriveFolder> createFolder(String name, {String? parentId});
}
