import 'package:flutter/material.dart';
import 'services/app_store.dart';
import 'services/reminder_service.dart';
import 'ui/home.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';
import 'services/drive_backup_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.tryLoad();
  final reminders = ReminderService();
  await reminders.initialize();
  DriveBackupService? backup;
  try {
    backup = await DriveBackupService.start(store);
  } catch (_) {
    backup = null; // the app still works without backup
  }
  runApp(PhotographApp(store: store, reminders: reminders, backup: backup));
}

class PhotographApp extends StatelessWidget {
  const PhotographApp({
    super.key,
    required this.store,
    required this.reminders,
    this.backup,
  });
  final AppStore store;
  final ReminderService reminders;
  final DriveBackupService? backup;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Jett's Archive",
    debugShowCheckedModeBanner: false,
    theme: photographTheme(),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (store.loadError != null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.folder_off_outlined,
                        size: 48,
                        color: Palette.wine,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Your journal needs a moment.',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'We couldn’t safely open your saved albums. Your existing files have been preserved. Check storage access and try again.',
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: store.tryLoad,
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
        return store.onboardingComplete
            ? HomeScreen(store: store, reminders: reminders, backup: backup)
            : Onboarding(onFinish: store.finishOnboarding);
      },
    ),
  );
}
