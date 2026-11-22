import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/pages/about/about_page.dart';
import 'package:localsend_app/util/native/platform_check.dart';

void main() {
  testWidgets('Harmony about page identifies this project and retains upstream attribution', (tester) async {
    debugHarmonyOSOverride = true;
    addTearDown(() => debugHarmonyOSOverride = null);

    await tester.pumpWidget(const MaterialApp(home: AboutPage()));
    expect(find.text('LocalSend Harmony'), findsOneWidget);
    expect(find.text('Based on LocalSend. Thanks to the original project and its contributors.'), findsOneWidget);
    expect(find.text('Project source'), findsOneWidget);
    expect(find.text('localsend.org'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
