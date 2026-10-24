import 'package:flutter/material.dart';

import '../services/drive_backup_engine.dart';
import '../services/drive_backup_service.dart';
import 'drive_backup_card.dart';
import 'theme.dart';

/// Google Drive icon for the top of the screen. It shows the backup state at a
/// glance and opens the backup panel (switch, save location, "Back up now").
class DriveTopButton extends StatelessWidget {
  const DriveTopButton({super.key, required this.service});
  final DriveBackupService service;

  Future<void> _open(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => DriveBackupDialog(service: service),
  );

  String _tooltip(BackupStatus status) {
    switch (status.phase) {
      case BackupPhase.off:
        return 'Google Drive backup (off)';
      case BackupPhase.idle:
        return 'Google Drive backup (on)';
      case BackupPhase.syncing:
        return 'Backing up to Google Drive…';
      case BackupPhase.waitingForInternet:
        return 'Google Drive backup (waiting for internet)';
      case BackupPhase.needsSignIn:
        return 'Google Drive backup (sign in again)';
      case BackupPhase.error:
        return 'Google Drive backup (problem)';
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<BackupStatus>(
    stream: service.statuses,
    initialData: service.status,
    builder: (context, snapshot) {
      final status = snapshot.data ?? service.status;
      final phase = status.phase;
      final attention =
          phase == BackupPhase.needsSignIn || phase == BackupPhase.error;
      final icon = Icon(
        Icons.add_to_drive_outlined,
        color: phase == BackupPhase.off ? Palette.sage : Palette.wine,
      );
      return Stack(
        alignment: Alignment.center,
        children: [
          // A thin spinner circles the icon while a backup is running.
          if (phase == BackupPhase.syncing)
            const SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Palette.wine,
              ),
            ),
          IconButton(
            tooltip: _tooltip(status),
            onPressed: () => _open(context),
            icon: attention
                ? Badge(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    smallSize: 9,
                    child: icon,
                  )
                : icon,
          ),
        ],
      );
    },
  );
}

/// The panel opened by [DriveTopButton].
class DriveBackupDialog extends StatelessWidget {
  const DriveBackupDialog({super.key, required this.service});
  final DriveBackupService service;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Palette.paper,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: const BorderSide(color: Palette.line),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: DriveBackupCard(service: service, framed: false),
            ),
          ],
        ),
      ),
    ),
  );
}
