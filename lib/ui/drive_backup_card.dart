import 'dart:async';

import 'package:flutter/material.dart';

import '../services/drive_backup_engine.dart';
import '../services/drive_backup_service.dart';
import 'drive_folder_picker.dart';
import 'theme.dart';

/// Settings card for the optional Google Drive backup.
class DriveBackupCard extends StatefulWidget {
  const DriveBackupCard({super.key, required this.service, this.framed = true});
  final DriveBackupService service;

  /// Draws the bordered "paper" box around the card. Turn off when the card is
  /// already inside a dialog or another box.
  final bool framed;

  @override
  State<DriveBackupCard> createState() => _DriveBackupCardState();
}

class _DriveBackupCardState extends State<DriveBackupCard> {
  bool busy = false;

  DriveBackupService get service => widget.service;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on StateError catch (e) {
      _message(e.message);
    } on DriveAuthException catch (e) {
      _message(e.message);
    } on DriveFailure catch (e) {
      _message(e.message);
    } catch (_) {
      _message(
        'Could not sign in to Google. Check your internet connection and '
        'try again.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Switch handler. When the backup is turned on for the first time the user
  /// is asked where to save it BEFORE anything is uploaded.
  Future<void> _toggle(bool value) => _run(() async {
    if (!value) {
      await service.disable();
      return;
    }
    await service.signInIfNeeded();
    if (!service.hasLocation && service.status.lastBackup == null) {
      if (!mounted) return;
      final choice = await showDriveFolderPicker(
        context,
        service,
        firstTime: true,
      );
      if (choice == null) return; // cancelled: the backup stays off
      await service.setLocation(choice);
    }
    await service.enable();
  });

  Future<void> _changeLocation() => _run(() async {
    final choice = await showDriveFolderPicker(context, service);
    if (choice == null) return;
    final before = service.locationLabel;
    await service.setLocation(choice);
    if (service.locationLabel != before) {
      _message(
        'Backup location changed. Everything will be copied to the new '
        'folder; copies already in Drive stay where they are.',
      );
    }
  });

  Future<void> _changeAccount() => _run(() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Google Drive account?'),
        content: const Text(
          'Your local albums and existing Drive backups stay '
          'where they are. After choosing an account, select a save location '
          'and turn backup on again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose account'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await service.changeAccount();
    _message(
      'Account changed. Choose a save location when you turn backup on.',
    );
  });

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _when(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${_months[t.month - 1]}, $hh:$mm';
  }

  String _statusText(BackupStatus s) {
    switch (s.phase) {
      case BackupPhase.off:
        return service.available
            ? 'Off. Your journal stays only on this device.'
            : 'Not set up in this build.';
      case BackupPhase.idle:
        return s.lastBackup == null
            ? 'On. The first backup starts when you are online.'
            : 'Backed up ${_when(s.lastBackup!.toLocal())}';
      case BackupPhase.syncing:
        return 'Backing up…';
      case BackupPhase.waitingForInternet:
        return 'Waiting for internet. It will back up when you are online.';
      case BackupPhase.needsSignIn:
        return 'Google needs you to sign in again.';
      case BackupPhase.error:
        return s.detail ?? 'The backup could not finish. It will retry.';
    }
  }

  Widget _locationRow() => InkWell(
    borderRadius: BorderRadius.circular(10),
    onTap: busy ? null : _changeLocation,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 20, color: Palette.wine),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saving to',
                  style: TextStyle(color: Palette.sage, fontSize: 12),
                ),
                Text(
                  service.locationLabel,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : _changeLocation,
            child: const Text('Change'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<BackupStatus>(
    stream: service.statuses,
    initialData: service.status,
    builder: (context, snapshot) {
      final status = snapshot.data ?? service.status;
      final on = service.enabled;
      final visibility = service.fullAccess
          ? 'The app can see your Drive folders so you can pick one. '
          : 'The app can only see what it saved itself. ';
      final body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined, color: Palette.wine),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Back up to Google Drive',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusText(status),
                      style: const TextStyle(color: Palette.sage),
                    ),
                  ],
                ),
              ),
              Switch(
                value: on,
                onChanged: busy || !service.available ? null : _toggle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Photos, videos and your journal are copied to your own Google '
            'Drive whenever you are online. Nothing is sent while you are '
            'offline. $visibility'
            'Items you delete here stay in Drive.',
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy || !service.available ? null : _changeAccount,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('Change Google Drive account'),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(),
            ),
          if (on) ...[
            const SizedBox(height: 12),
            _locationRow(),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              children: [
                if (status.phase == BackupPhase.needsSignIn)
                  FilledButton(
                    onPressed: busy ? null : () => _run(service.reconnect),
                    child: const Text('Sign in again'),
                  )
                else
                  OutlinedButton(
                    onPressed: busy || status.phase == BackupPhase.syncing
                        ? null
                        : () => unawaited(service.backupNow()),
                    child: const Text('Back up now'),
                  ),
              ],
            ),
          ],
        ],
      );
      if (!widget.framed) return body;
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Palette.paper,
          border: Border.all(color: Palette.line),
          borderRadius: BorderRadius.circular(16),
        ),
        child: body,
      );
    },
  );
}
