import 'package:flutter/material.dart';
import 'services/app_store.dart';
import 'services/reminder_service.dart';
import 'ui/home.dart';
import 'ui/onboarding.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore();
  await store.tryLoad();
  final reminders = ReminderService();
  await reminders.initialize();
  runApp(PhotographApp(store: store, reminders: reminders));
}

class PhotographApp extends StatelessWidget {
  const PhotographApp({
    super.key,
    required this.store,
    required this.reminders,
  });
  final AppStore store;
  final ReminderService reminders;
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
            ? HomeScreen(store: store, reminders: reminders)
            : Onboarding(onFinish: store.finishOnboarding);
      },
    ),
  );
}
