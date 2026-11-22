import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/widget/harmony_layout.dart';
import 'package:localsend_app/widget/responsive_wrap_view.dart';

void main() {
  for (final size in [const Size(280, 500), const Size(360, 720), const Size(900, 650)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Harmony sections fit $size with text scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var presses = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        const HarmonyPageHeading(title: 'Settings and device preferences'),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: HarmonySettingRow(
                              label: 'A long setting label that must remain readable',
                              description: 'A longer description should wrap without obscuring the control.',
                              child: Switch(value: true, onChanged: (_) => presses++),
                            ),
                          ),
                        ),
                        HarmonySectionToolbar(
                          title: 'Nearby devices',
                          actions: List.generate(
                            4,
                            (index) => IconButton(
                              onPressed: () => presses++,
                              icon: const Icon(Icons.settings),
                              tooltip: 'Action $index',
                            ),
                          ),
                        ),
                        ResponsiveWrapView(
                          outerHorizontalPadding: 16,
                          outerVerticalPadding: 8,
                          childPadding: 8,
                          minChildWidth: 90,
                          children: List.generate(
                            4,
                            (index) => FilledButton(
                              onPressed: () => presses++,
                              child: Text('Add $index'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final control = find.byType(Switch);
        await tester.ensureVisible(control);
        await tester.tap(control);
        await tester.pumpAndSettle();
        expect(presses, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
