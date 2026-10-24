import 'package:flutter/material.dart';

import '../services/drive_backup_engine.dart';
import '../services/drive_backup_service.dart';
import '../services/drive_folders.dart';
import 'theme.dart';

/// Opens the folder picker. Returns where the user wants the backup saved, or
/// null when they cancel.
///
/// Set [firstTime] when the picker is shown while switching the backup on, so
/// the wording matches.
Future<DriveLocation?> showDriveFolderPicker(
  BuildContext context,
  DriveBackupService service, {
  bool firstTime = false,
}) => showDialog<DriveLocation>(
  context: context,
  builder: (_) => DriveFolderPicker(service: service, firstTime: firstTime),
);

/// Lets the user browse their Google Drive, make new folders and choose the
/// one the backup is saved in.
class DriveFolderPicker extends StatefulWidget {
  const DriveFolderPicker({
    super.key,
    required this.service,
    this.firstTime = false,
  });

  final DriveBackupService service;
  final bool firstTime;

  @override
  State<DriveFolderPicker> createState() => _DriveFolderPickerState();
}

class _DriveFolderPickerState extends State<DriveFolderPicker> {
  /// The folders opened so far, from My Drive down to the current one.
  final List<DriveFolder> _trail = [
    const DriveFolder(id: DriveFolder.rootId, name: 'My Drive'),
  ];
  List<DriveFolder> _folders = const [];
  bool _loading = true;
  String? _error;
  int _ticket = 0; // ignores answers that arrive after the user moved on

  DriveFolder get _current => _trail.last;
  bool get _atRoot => _trail.length == 1;
  String? get _parentId => _atRoot ? null : _current.id;
  String get _path => _trail.map((f) => f.name).join(' › ');

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _describe(Object error) {
    if (error is DriveAuthException) return error.message;
    if (error is DriveFailure) return error.message;
    if (error is StateError) return error.message;
    return 'Could not load your Drive folders. Check your internet '
        'connection and try again.';
  }

  Future<void> _load() async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.listFolders(parentId: _parentId);
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _folders = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _folders = const [];
        _loading = false;
        _error = _describe(error);
      });
    }
  }

  void _open(DriveFolder folder) {
    _trail.add(folder);
    _load();
  }

  void _up() {
    if (_atRoot) return;
    _trail.removeLast();
    _load();
  }

  Future<void> _newFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewFolderDialog(),
    );
    if (name == null || !mounted) return;
    setState(() => _loading = true);
    try {
      final created = await widget.service.createFolder(
        name,
        parentId: _parentId,
      );
      if (!mounted) return;
      _trail.add(created); // step straight into the new folder
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _describe(error);
      });
    }
  }

  void _choose() {
    final location = _atRoot
        ? DriveLocation(
            folderId: null,
            label: 'My Drive › ${DriveBackupEngine.folderName}',
          )
        : DriveLocation(folderId: _current.id, label: _path);
    Navigator.of(context).pop(location);
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: Palette.sage),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(
        child: Text(
          widget.service.fullAccess
              ? 'No folders here yet.\nUse “New folder” to make one.'
              : 'No folders to show here yet.\nUse “New folder” to make one.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.sage, height: 1.5),
        ),
      );
    }
    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (context, i) {
        final folder = _folders[i];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined, color: Palette.wine),
          title: Text(
            folder.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(folder),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Palette.paper,
    title: Text(
      widget.firstTime ? 'Where should it be saved?' : 'Choose a location',
    ),
    content: SizedBox(
      width: 440,
      height: 380,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Up one folder',
                onPressed: _atRoot || _loading ? null : _up,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
              Expanded(
                child: Text(
                  _path,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const Divider(height: 8, color: Palette.line),
          Expanded(child: _body()),
          const SizedBox(height: 8),
          Text(
            _atRoot
                ? 'Open a folder, or save in the default '
                      '“${DriveBackupEngine.folderName}” folder.'
                : 'The backup will be saved in this folder.',
            style: const TextStyle(color: Palette.sage, fontSize: 12),
          ),
          if (!widget.service.fullAccess) ...[
            const SizedBox(height: 6),
            const Text(
              'This app can only see folders it created. Make a new folder '
              'here; you can move it anywhere in Drive later and the backup '
              'will keep following it.',
              style: TextStyle(color: Palette.sage, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: _loading || _error != null ? null : _newFolder,
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('New folder'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _loading ? null : _choose,
        child: Text(_atRoot ? 'Use default' : 'Save here'),
      ),
    ],
  );
}

/// Asks for the name of a new folder.
class _NewFolderDialog extends StatefulWidget {
  const _NewFolderDialog();

  @override
  State<_NewFolderDialog> createState() => _NewFolderDialogState();
}

class _NewFolderDialogState extends State<_NewFolderDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: Palette.paper,
    title: const Text('New folder'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(hintText: 'Folder name'),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}
