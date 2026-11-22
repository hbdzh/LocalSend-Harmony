import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';

void main() {
  test('Harmony theme preserves the selected accent in light and dark mode', () {
    for (final brightness in Brightness.values) {
      final base = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple, brightness: brightness),
      );
      final theme = harmonyTheme(base);
      expect(theme.colorScheme.primary, base.colorScheme.primary);
      expect(theme.scaffoldBackgroundColor.computeLuminance() > 0.5, brightness == Brightness.light);
    }
  });

  testWidgets('navigation and cards fit a narrow phone window', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
        home: Scaffold(
          body: ListView(
            children: [
              Card(
                child: Padding(padding: const EdgeInsets.all(24), child: Text('LocalSend')),
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.wifi), label: 'Receive'),
              NavigationDestination(icon: Icon(Icons.send), label: 'Send'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('LocalSend'), findsOneWidget);
  });

  test('menus and controls follow the Harmony palette in both brightness modes', () {
    for (final brightness in Brightness.values) {
      final base = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.purple, brightness: brightness),
      );
      final theme = harmonyTheme(base);
      expect(theme.popupMenuTheme.color, theme.cardTheme.color);
      expect(theme.switchTheme.trackColor!.resolve({WidgetState.selected}), base.colorScheme.primary);
      expect(theme.switchTheme.trackColor!.resolve({WidgetState.disabled, WidgetState.selected}), isNot(base.colorScheme.primary));
      expect(theme.checkboxTheme.fillColor!.resolve({WidgetState.selected}), base.colorScheme.primary);
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
    }
  });

  for (final size in [const Size(320, 640), const Size(1024, 720)]) {
    for (final brightness in Brightness.values) {
      testWidgets('menu and dialog remain usable at $size in $brightness', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var chosen = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: harmonyTheme(
              ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness),
              ),
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    PopupMenuButton<int>(
                      key: const Key('menu'),
                      onSelected: (_) => chosen = true,
                      itemBuilder: (_) => [const PopupMenuItem(value: 1, child: Text('Select item'))],
                    ),
                    TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Dialog'),
                          content: const TextField(),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                        ),
                      ),
                      child: const Text('Open dialog'),
                    ),
                    Switch(value: true, onChanged: (_) {}),
                    Checkbox(value: true, onChanged: (_) {}),
                    Slider(value: 0.5, onChanged: (_) {}),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select item'));
        await tester.pumpAndSettle();
        expect(chosen, isTrue);
        await tester.tap(find.text('Open dialog'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
