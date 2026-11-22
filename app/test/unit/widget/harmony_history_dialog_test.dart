import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/receive_history_entry.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:localsend_app/widget/dialogs/file_info_dialog.dart';
import 'package:localsend_app/widget/dialogs/history_clear_dialog.dart';
import 'package:localsend_app/widget/dialogs/pin_dialog.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:system_date_time_format/system_date_time_format.dart';

import '../../mocks.mocks.dart';

class _DateFormat extends Fake implements SystemDateTimeFormat {
  @override
  Future<Patterns> getAllPatterns() async => const Patterns();
}

void main() {
  setUpAll(() async => initializeDateFormatting());
  testWidgets('opening a history entry invokes the system file viewer', (tester) async {
    debugHarmonyOSOverride = true;
    const channel = MethodChannel('org.localsend.localsend_app/harmony_device');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? opened;
    messenger.setMockMethodCallHandler(channel, (call) async {
      opened = call;
      return null;
    });
    addTearDown(() {
      debugHarmonyOSOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    final entry = ReceiveHistoryEntry(
      id: 'id',
      fileName: 'report.pdf',
      fileType: FileType.other,
      path: '/private/report.pdf',
      savedToGallery: false,
      isMessage: false,
      fileSize: 1,
      senderAlias: 'Device',
      timestamp: DateTime.utc(2025),
    );
    final persistence = MockPersistenceService();
    when(persistence.getReceiveHistory()).thenReturn([entry]);
    await tester.pumpWidget(
      RefenaScope(
        overrides: [persistenceProvider.overrideWithValue(persistence)],
        child: SDTFScope(
          format: _DateFormat(),
          child: MaterialApp(
            theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
            home: const ReceiveHistoryPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('report.pdf'));
    await tester.pumpAndSettle();
    expect(opened?.method, 'openFile');
    expect((opened?.arguments as Map)['path'], '/private/report.pdf');
  });

  for (final size in [const Size(280, 500), const Size(360, 720), const Size(600, 300), const Size(1024, 700)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Harmony history and file details fit $size scale=$scale', (tester) async {
        debugHarmonyOSOverride = true;
        addTearDown(() => debugHarmonyOSOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final entry = ReceiveHistoryEntry(
          id: 'id',
          fileName: 'a-very-long-file-name-包含中文-for-history-testing.txt',
          fileType: FileType.other,
          path: '/private/very-long-folder-name/other-folder/file.txt',
          savedToGallery: false,
          isMessage: false,
          fileSize: 12345678,
          senderAlias: 'A very long device name',
          timestamp: DateTime.utc(2025),
        );
        final persistence = MockPersistenceService();
        when(persistence.getReceiveHistory()).thenReturn([entry]);
        await tester.pumpWidget(
          RefenaScope(
            overrides: [persistenceProvider.overrideWithValue(persistence)],
            child: SDTFScope(
              format: _DateFormat(),
              child: MaterialApp(
                theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                    child: const ReceiveHistoryPage(),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(entry.fileName), findsOneWidget);
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(t.receiveHistoryPage.entryActions.info).last);
        await tester.pumpAndSettle();
        expect(find.byType(FileInfoDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        final dialogSize = tester.getSize(find.byType(Dialog));
        expect(dialogSize.width, lessThanOrEqualTo(size.width));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      });
    }
  }

  for (final size in [const Size(280, 500), const Size(600, 300)]) {
    testWidgets('long error, confirmation and PIN dialogs fit $size with large text', (tester) async {
      debugHarmonyOSOverride = true;
      addTearDown(() => debugHarmonyOSOverride = null);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
              child: Scaffold(
                body: Column(
                  children: [
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => ErrorDialog(error: 'Long error details ' * 50),
                      ),
                      child: const Text('Error'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<void>(context: context, builder: (_) => const HistoryClearDialog()),
                      child: const Text('Clear'),
                    ),
                    TextButton(
                      onPressed: () => showDialog<void>(context: context, builder: (_) => const PinDialog(obscureText: true, showInvalidPin: true)),
                      child: const Text('Pin'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (final button in ['Error', 'Clear', 'Pin']) {
        await tester.tap(find.text(button).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsOneWidget);
        Navigator.of(tester.element(find.byType(AlertDialog))).pop();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('history clear requires confirmation and clears only after approval', (tester) async {
    debugHarmonyOSOverride = true;
    addTearDown(() => debugHarmonyOSOverride = null);
    final entry = ReceiveHistoryEntry(
      id: 'id',
      fileName: 'item.txt',
      fileType: FileType.other,
      path: '/private/item.txt',
      savedToGallery: false,
      isMessage: false,
      fileSize: 1,
      senderAlias: 'Device',
      timestamp: DateTime.utc(2025),
    );
    final persistence = MockPersistenceService();
    when(persistence.getReceiveHistory()).thenReturn([entry]);
    when(persistence.setReceiveHistory(any)).thenAnswer((_) async {});
    await tester.pumpWidget(
      RefenaScope(
        overrides: [persistenceProvider.overrideWithValue(persistence)],
        child: SDTFScope(
          format: _DateFormat(),
          child: MaterialApp(
            theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
            home: const ReceiveHistoryPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.receiveHistoryPage.deleteHistory));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryClearDialog), findsOneWidget);
    await tester.tap(find.text(t.general.cancel));
    await tester.pumpAndSettle();
    verifyNever(persistence.setReceiveHistory(any));
    await tester.tap(find.text(t.receiveHistoryPage.deleteHistory));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.general.delete).last);
    await tester.pumpAndSettle();
    verify(persistence.setReceiveHistory([])).called(1);
    expect(find.text(entry.fileName), findsNothing);
  });

  testWidgets('PIN dialog remains accessible when the keyboard reduces the viewport', (tester) async {
    debugHarmonyOSOverride = true;
    addTearDown(() => debugHarmonyOSOverride = null);
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => const PinDialog(obscureText: true, showInvalidPin: true)),
              child: const Text('Open PIN'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open PIN'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextFormField), '123456');
    expect(find.text('123456'), findsOneWidget);
  });
}
