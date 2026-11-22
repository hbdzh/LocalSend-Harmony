import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/widget/responsive_builder.dart';

void main() {
  test('keeps navigation accessible as the window is resized', () {
    expect(const SizingInformation(699, 700).useBottomNavigation, isTrue);
    expect(const SizingInformation(700, 700).useBottomNavigation, isFalse);
    expect(const SizingInformation(1100, 399).useBottomNavigation, isTrue);
    expect(const SizingInformation(1100, 400).useBottomNavigation, isFalse);
  });

  testWidgets('recomputes navigation mode when the window size changes', (tester) async {
    Widget screen(Size size) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: ResponsiveBuilder(
          builder: (sizing) => Text(sizing.useBottomNavigation ? 'bottom' : 'rail'),
        ),
      ),
    );

    await tester.pumpWidget(screen(const Size(1100, 800)));
    expect(find.text('rail'), findsOneWidget);
    await tester.pumpWidget(screen(const Size(1100, 350)));
    expect(find.text('bottom'), findsOneWidget);
    await tester.pumpWidget(screen(const Size(500, 800)));
    expect(find.text('bottom'), findsOneWidget);
  });
}
