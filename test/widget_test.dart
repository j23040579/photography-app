import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photograph/domain/models.dart';
import 'package:photograph/main.dart';
import 'package:photograph/services/app_store.dart';
import 'package:photograph/services/reminder_service.dart';

// Native camera, file pickers and notification delivery require device tests.
// These tests exercise actual widgets and durable local writes without plugins.
class _UnavailableReminders extends ReminderService {
  _UnavailableReminders() {
    available = false;
    status = 'Notifications are unavailable on this test device.';
  }

  @override
  Future<void> restoreReminders(Iterable<Album> albums) async {}
}

Future<void> _tapAndWaitForWrite(
  WidgetTester tester,
  AppStore store,
  Finder finder,
  bool Function() committed,
) async {
  // File IO runs in the real asynchronous zone; pumpAndSettle alone cannot
  // guarantee that a persistent write has completed.
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(finder);
  });
  var saved = false;
  for (var attempt = 0; attempt < 200 && !saved; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!committed()) return;
      final root = await store.directory;
      final state = File('${root.path}/photograph.json');
      if (!await state.exists()) return;
      final expected = jsonEncode({
        'version': 1,
        'onboardingComplete': store.onboardingComplete,
        'albums': store.albums.map((a) => a.toJson()).toList(),
        'model': store.engine.toJson(),
      });
      saved =
          await state.readAsString() == expected &&
          !tester
              .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
              .any((widget) => widget.absorbing);
    });
  }
  expect(
    saved,
    isTrue,
    reason: 'The local JSON must contain the committed edit.',
  );
  expect(
    committed(),
    isTrue,
    reason: 'The UI action must commit to local storage.',
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'first-use guide, album, editable ideas and journal persist at ${size.width.toInt()}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late Directory directory;
        late AppStore store;
        await tester.runAsync(() async {
          directory = await Directory.systemTemp.createTemp(
            'photograph-widget-',
          );
          store = AppStore(directory: directory);
          await store.load();
        });
        addTearDown(() async {
          store.dispose();
          await directory.delete(recursive: true);
        });
        final reminders = _UnavailableReminders();
        await tester.pumpWidget(
          PhotographApp(store: store, reminders: reminders),
        );
        await tester.pumpAndSettle();
        expect(find.text('Make room for\nthe little things.'), findsOneWidget);

        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(
          find.text('A little intention.\nA lot of memories.'),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Next'));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(
          find.text('Tomorrow starts\nwith a little plan.'),
          findsOneWidget,
        );
        expect(find.textContaining('one day ahead'), findsOneWidget);
        await tester.ensureVisible(find.text('Start my journal'));
        await _tapAndWaitForWrite(
          tester,
          store,
          find.text('Start my journal'),
          () => store.onboardingComplete,
        );
        expect(
          find.text('Life happens.\nKeep a little of it.'),
          findsOneWidget,
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Guide and home must fit.',
        );

        await tester.tap(
          find.widgetWithText(FloatingActionButton, 'Create album'),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'Friday friends');
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('Party'),
          ),
        );
        final create = find.text('Create album & find my photo ideas');
        await tester.ensureVisible(create);
        await _tapAndWaitForWrite(
          tester,
          store,
          create,
          () => store.albums.isNotEmpty,
        );
        expect(store.albums.single.category, PlaceCategory.party);
        expect(store.albums.single.prompts.length, 5);
        expect(find.text('Friday friends'), findsWidgets);
        expect(find.text('Take a photo'), findsOneWidget);
        expect(find.text('Add videos'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'Album detail must fit.',
        );

        final edit = find.byTooltip('Edit this idea').first;
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        expect(find.text('Make this idea yours'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'A photo with my three oldest friends',
        );
        await _tapAndWaitForWrite(
          tester,
          store,
          find.text('Save'),
          () =>
              store.albums.single.prompts.first.text ==
              'A photo with my three oldest friends',
        );
        expect(store.albums.single.prompts.first.edited, isTrue);
        expect(
          find.text('A photo with my three oldest friends'),
          findsOneWidget,
        );

        final like = find.byTooltip('I like this idea').first;
        await tester.ensureVisible(like);
        await _tapAndWaitForWrite(
          tester,
          store,
          like,
          () => store.engine.feedbackCount == 1,
        );
        expect(store.engine.feedbackCount, 1);

        final notes = find.text('Notes');
        await tester.ensureVisible(notes);
        await tester.tap(notes);
        await tester.pumpAndSettle();
        final fifthStar = find.byTooltip('5 stars');
        await tester.ensureVisible(fifthStar);
        await _tapAndWaitForWrite(
          tester,
          store,
          fifthStar,
          () => store.albums.single.rating == 5,
        );
        await tester.ensureVisible(find.text('Write a note'));
        await tester.tap(find.text('Write a note'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'The music, the laughter, and a table full of friends.',
        );
        await _tapAndWaitForWrite(
          tester,
          store,
          find.text('Save'),
          () =>
              store.albums.single.notes ==
              'The music, the laughter, and a table full of friends.',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'Editing and notes must fit.',
        );

        // Reopen a fresh store from the same device directory: this validates
        // durable state rather than just the live ChangeNotifier values.
        late AppStore reopened;
        await tester.runAsync(() async {
          reopened = AppStore(directory: directory);
          await reopened.load();
        });
        addTearDown(reopened.dispose);
        expect(reopened.onboardingComplete, isTrue);
        expect(reopened.albums.single.title, 'Friday friends');
        expect(reopened.albums.single.rating, 5);
        expect(
          reopened.albums.single.notes,
          'The music, the laughter, and a table full of friends.',
        );
        expect(
          reopened.albums.single.prompts.first.text,
          'A photo with my three oldest friends',
        );
        expect(reopened.engine.feedbackCount, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          PhotographApp(store: reopened, reminders: reminders),
        );
        await tester.pumpAndSettle();
        expect(find.text('Make room for\nthe little things.'), findsNothing);
        expect(find.text('Friday friends'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
