import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/util/native/harmony_recovery_ui.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _Send extends SendNotifier {
  @override
  Map<String, SendSessionState> init() => {};
}

void main() {
  testWidgets('reopens unfinished sends from the recovery menu', (tester) async {
    final root = Directory.systemTemp.createTempSync('localsend-recovery-ui-');
    HarmonyTransferRecovery.directory = root;
    addTearDown(() {
      HarmonyTransferRecovery.directory = null;
      root.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      RefenaScope(
        overrides: [sendProvider.overrideWithNotifier((_) => _Send())],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => HarmonyRecoveryUi.open(context),
                child: const Text('Open recovery'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unfinished sends'));
    await tester.pumpAndSettle();
    expect(find.text('No unfinished sends.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    expect(find.text('Unfinished sends'), findsOneWidget);
  });

  testWidgets('explains paused cleanup for an unreadable recovery record', (tester) async {
    final root = Directory.systemTemp.createTempSync('localsend-broken-recovery-');
    final session = Directory('${root.path}/session')..createSync();
    File('${session.path}/broken.json').writeAsStringSync('{');
    HarmonyTransferRecovery.directory = root;
    addTearDown(() {
      HarmonyTransferRecovery.directory = null;
      root.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      RefenaScope(
        overrides: [sendProvider.overrideWithNotifier((_) => _Send())],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => HarmonyRecoveryUi.open(context),
                child: const Text('Open recovery'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open recovery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unfinished sends'));
    await tester.pumpAndSettle();
    expect(find.textContaining('temporary file cleanup is paused'), findsOneWidget);
    await tester.tap(find.text('Clear records'));
    await tester.pumpAndSettle();
    expect(session.existsSync(), isFalse);
  });
}
