import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photograph/services/drive_backup_engine.dart';
import 'package:photograph/services/drive_backup_service.dart';
import 'package:photograph/services/google_drive_auth.dart';
import 'package:photograph/ui/drive_button.dart';
import 'package:photograph/ui/theme.dart';
import 'drive_backup_engine_test.dart' show FakeDrive;

class ChoosingAuth extends GoogleDriveAuth {
  ChoosingAuth(Directory superRoot) : super(root: superRoot);
  bool choseAccount = false;
  bool cancelled = false;
  Completer<void>? hold;
  final started = Completer<void>();
  @override
  bool get configured => true;
  @override
  Future<void> signIn({bool forceAccountSelection = false}) async {
    choseAccount = forceAccountSelection;
    if (!started.isCompleted) started.complete();
    await hold?.future;
    if (cancelled) throw const DriveAuthException('Cancelled');
  }
}

class BlockingDrive extends FakeDrive {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String> create({
    required String name,
    required String parentId,
    required File file,
    required String mimeType,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.create(
      name: name,
      parentId: parentId,
      file: file,
      mimeType: mimeType,
    );
  }
}

void main() {
  late Directory root;
  late ChoosingAuth auth;
  late DriveBackupEngine engine;
  late DriveBackupService service;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('drive-account-');
    auth = ChoosingAuth(root);
    engine = DriveBackupEngine(
      root: root,
      storage: FakeDrive(),
      isOnline: () async => true,
      debounce: const Duration(hours: 1),
    );
    await engine.load();
    service = DriveBackupService.withDependencies(
      engine: engine,
      authentication: auth,
    );
  });
  tearDown(() async {
    service.dispose();
    await root.delete(recursive: true);
  });

  test(
    'chooser preserves OAuth security parameters and requests account selection',
    () {
      final original = Uri.https('accounts.google.com', '/o/oauth2/auth', {
        'state': 'random',
        'code_challenge': 'pkce',
        'redirect_uri': 'http://localhost:1234',
        'prompt': 'consent',
      });
      final selected = GoogleDriveAuth.authorizationUrl(
        original,
        forceAccountSelection: true,
      );
      expect(selected.queryParameters['prompt'], 'select_account consent');
      for (final key in ['state', 'code_challenge', 'redirect_uri']) {
        expect(selected.queryParameters[key], original.queryParameters[key]);
      }
      expect(
        GoogleDriveAuth.authorizationUrl(
          original,
          forceAccountSelection: false,
        ),
        original,
      );
    },
  );

  test(
    'successful switch clears account-specific targets durably and keeps local journal',
    () async {
      await File('${root.path}/photograph.json').writeAsString('local journal');
      await File('${root.path}/drive_backup.json').writeAsString(
        jsonEncode({
          'enabled': true,
          'folderId': 'old-folder',
          'locationLabel': 'Old account',
          'customLocation': true,
          'mediaFolderId': 'old-media',
          'journalFileId': 'old-journal',
          'journalMarker': 'old',
          'lastBackup': DateTime(2026).toIso8601String(),
          'uploaded': {'1-2.jpg': 'old-file'},
        }),
      );
      await engine.load();
      await service.changeAccount();
      expect(auth.choseAccount, isTrue);
      expect(service.enabled, isFalse);
      expect(service.hasLocation, isFalse);
      expect(service.status.lastBackup, isNull);
      final saved = jsonDecode(
        await File('${root.path}/drive_backup.json').readAsString(),
      );
      expect(saved['folderId'], isNull);
      expect(saved['journalFileId'], isNull);
      expect(saved['uploaded'], isEmpty);
      expect(
        await File('${root.path}/photograph.json').readAsString(),
        'local journal',
      );
    },
  );

  test(
    'cancelled chooser restores previous account destination and backup preference',
    () async {
      await engine.setLocation(
        folderId: 'original',
        label: 'My original folder',
      );
      await engine.setEnabled(true);
      auth.cancelled = true;
      await expectLater(
        service.changeAccount(),
        throwsA(isA<DriveAuthException>()),
      );
      expect(engine.locationLabel, 'My original folder');
      expect(engine.enabled, isTrue);
      await engine.setEnabled(false);
    },
  );

  test('waits for an in-flight upload before changing the account', () async {
    service.dispose();
    final blocking = BlockingDrive();
    await File('${root.path}/photograph.json').writeAsString('{}');
    engine = DriveBackupEngine(
      root: root,
      storage: blocking,
      isOnline: () async => true,
      debounce: const Duration(hours: 1),
    );
    await engine.load();
    service = DriveBackupService.withDependencies(
      engine: engine,
      authentication: auth,
    );
    await engine.setEnabled(true);
    final sync = engine.syncNow();
    await blocking.started.future;
    final changing = service.changeAccount();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(auth.choseAccount, isFalse);
    blocking.release.complete();
    await sync;
    await changing;
    expect(auth.choseAccount, isTrue);
    expect(service.enabled, isFalse);
  });

  test(
    'other backup controls cannot re-enable uploads during the chooser',
    () async {
      auth.hold = Completer<void>();
      final changing = service.changeAccount();
      await auth.started.future;
      await expectLater(service.enable(), throwsA(isA<StateError>()));
      await expectLater(service.changeAccount(), throwsA(isA<StateError>()));
      expect(engine.enabled, isFalse);
      auth.hold!.complete();
      await changing;
      expect(engine.enabled, isFalse);
    },
  );

  testWidgets('Drive icon opens account switching even with backup off', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: photographTheme(),
        home: Scaffold(body: DriveTopButton(service: service)),
      ),
    );
    await tester.tap(find.byTooltip('Google Drive backup (off)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change Google Drive account'));
    // The card deliberately animates while the confirmation is pending.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Choose account'), findsOneWidget);
    expect(auth.choseAccount, isFalse);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(auth.choseAccount, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
