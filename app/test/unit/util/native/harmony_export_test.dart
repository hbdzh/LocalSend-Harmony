import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_export.dart';
import 'package:localsend_app/widget/harmony_export_folder_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.localsend.localsend_app/harmony_device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('remembers the chosen folder for the save picker and preserves it on cancel', () async {
    var cancel = false;
    Map<Object?, Object?>? arguments;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'chooseExportFolder') return cancel ? null : 'file://docs/selected';
      arguments = Map<Object?, Object?>.from(call.arguments as Map);
      return true;
    });
    expect(await chooseHarmonyExportFolder(), 'file://docs/selected');
    cancel = true;
    expect(await chooseHarmonyExportFolder(), isNull);
    expect(await exportHarmonyFile('/private/hello.txt'), isTrue);
    expect(arguments?['preferredFolder'], 'file://docs/selected');
    await clearHarmonyExportFolder();
    expect(await getHarmonyExportFolder(), isNull);
  });

  testWidgets('selects and clears the preferred export folder', (tester) async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'file://docs/selected');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HarmonyExportFolderSetting())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Change'), findsOneWidget);
    expect(await getHarmonyExportFolder(), 'file://docs/selected');
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    expect(find.text('Choose'), findsOneWidget);
    expect(await getHarmonyExportFolder(), isNull);
  });

  test('propagates an export failure', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'export_failed'));
    await expectLater(exportHarmonyFile('/private/received/file.txt'), throwsA(isA<PlatformException>()));
  });
  testWidgets('save cancellation stays quiet and write failure is shown', (tester) async {
    var fail = false;
    messenger.setMockMethodCallHandler(channel, (_) async {
      if (fail) throw PlatformException(code: 'write_failed', message: 'Disk full');
      return false;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => saveReceivedFile(context, '/private/file.txt'), child: const Text('Save')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    fail = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Disk full'), findsOneWidget);
  });
}
