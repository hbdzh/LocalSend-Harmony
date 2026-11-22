import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/open_file.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/model/file_type.dart';

void main() {
  testWidgets('offers save if the system cannot open a received file', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.localsend.localsend_app/harmony_device');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openFile') throw PlatformException(code: 'open_file_failed');
      return null;
    });
    debugHarmonyOSOverride = true;
    addTearDown(() {
      debugHarmonyOSOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => openFile(context, FileType.other, '/private/report.pdf'),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open file'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
