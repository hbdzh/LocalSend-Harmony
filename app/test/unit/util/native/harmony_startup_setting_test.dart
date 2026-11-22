import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_window.dart';
import 'package:localsend_app/widget/harmony_startup_setting.dart';

void main() {
  testWidgets('shows system startup status and refreshes after user changes it', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var enabled = false;
    messenger.setMockMethodCallHandler(HarmonyWindow.channel, (call) async => {'supported': true, 'enabled': enabled});
    addTearDown(() => messenger.setMockMethodCallHandler(HarmonyWindow.channel, null));
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HarmonyStartupSetting())));
    await tester.pumpAndSettle();
    expect(find.text('Start at login: Disabled'), findsOneWidget);
    enabled = true;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('Start at login: Enabled'), findsOneWidget);
    expect(find.text('Change this in system app launch settings.'), findsOneWidget);
  });
}
