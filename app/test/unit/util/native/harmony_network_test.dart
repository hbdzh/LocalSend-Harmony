import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_network.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('coalesces network events and refreshes again for a later change', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HarmonyNetwork.channel, (_) async => null);
    addTearDown(() {
      HarmonyNetwork.channel.setMethodCallHandler(null);
      messenger.setMockMethodCallHandler(HarmonyNetwork.channel, null);
    });
    var count = 0;
    await HarmonyNetwork.start(() async {
      count++;
    });
    Future<void> change() async {
      await messenger.handlePlatformMessage(
        HarmonyNetwork.channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('changed')),
        (_) {},
      );
    }

    await change();
    await change();
    await tester.pump(const Duration(milliseconds: 501));
    expect(count, 1);
    await change();
    await tester.pump(const Duration(milliseconds: 501));
    expect(count, 2);
  });

  testWidgets('waits for the startup lookup before applying a later network change', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HarmonyNetwork.channel, (_) async => null);
    addTearDown(() {
      HarmonyNetwork.channel.setMethodCallHandler(null);
      messenger.setMockMethodCallHandler(HarmonyNetwork.channel, null);
    });
    final first = Completer<void>();
    var calls = 0;
    var running = 0;
    var maximumRunning = 0;
    Future<void> refresh() async {
      calls++;
      running++;
      if (running > maximumRunning) maximumRunning = running;
      if (calls == 1) await first.future;
      running--;
    }

    await HarmonyNetwork.start(refresh);
    Future<void> change() => messenger.handlePlatformMessage(
      HarmonyNetwork.channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('changed')),
      (_) {},
    );
    unawaited(HarmonyNetwork.refreshInitially(refresh));
    await tester.pump();
    await change();
    await tester.pump(const Duration(milliseconds: 501));
    expect(calls, 1);
    first.complete();
    await tester.pump();
    expect(calls, 2);
    expect(maximumRunning, 1);
  });
}
