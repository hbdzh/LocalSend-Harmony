import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_window.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

void main() {
  testWidgets('disposing an older page keeps the current window handler', (tester) async {
    late BuildContext oldContext;
    late BuildContext newContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Builder(
              builder: (context) {
                oldContext = context;
                return const SizedBox();
              },
            ),
            Builder(
              builder: (context) {
                newContext = context;
                return const SizedBox();
              },
            ),
          ],
        ),
      ),
    );
    HarmonyWindow.attach(oldContext);
    HarmonyWindow.attach(newContext);
    HarmonyWindow.detach(oldContext);
    addTearDown(HarmonyWindow.detach);
    final reply = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      HarmonyWindow.channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('willClose', {'trayEnabled': true})),
      reply.complete,
    );
    expect(const StandardMethodCodec().decodeEnvelope((await reply.future)!), 'minimize');
  });

  testWidgets('offers cancel, minimize or close during a transfer', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const background = MethodChannel('org.localsend.localsend_app/harmony_background');
    messenger.setMockMethodCallHandler(background, (_) async => null);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    TransferNotification.harmonyOverride = true;
    TransferNotification.init(
      NotificationStrings(
        titleReceiving: 'Receiving',
        titleSending: 'Sending',
        remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
        remainingTimeLong: ({required h, required m}) => '$h:$m',
      ),
    );
    addTearDown(() {
      HarmonyWindow.detach();
      TransferNotification.harmonyOverride = null;
      messenger.setMockMethodCallHandler(background, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            HarmonyWindow.attach(context);
            return const Scaffold();
          },
        ),
      ),
    );
    TransferNotification.start(sessionId: 'window', receiving: true);
    final reply = Completer<ByteData?>();
    unawaited(
      messenger.handlePlatformMessage(
        HarmonyWindow.channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('willClose')),
        reply.complete,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Transfer in progress'), findsOneWidget);
    await tester.tap(find.text('Minimize'));
    await tester.pumpAndSettle();
    expect(const StandardMethodCodec().decodeEnvelope((await reply.future)!), 'minimize');
    TransferNotification.stop('window');
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tray close warns until the background task is confirmed', (tester) async {
    final progress = Completer<void>();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const background = MethodChannel('org.localsend.localsend_app/harmony_background');
    messenger.setMockMethodCallHandler(background, (call) async {
      if (call.method == 'progress') await progress.future;
      return null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    TransferNotification.harmonyOverride = true;
    TransferNotification.init(
      NotificationStrings(
        titleReceiving: 'Receiving',
        titleSending: 'Sending',
        remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
        remainingTimeLong: ({required h, required m}) => '$h:$m',
      ),
    );
    addTearDown(() {
      HarmonyWindow.detach();
      TransferNotification.harmonyOverride = null;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(background, null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            HarmonyWindow.attach(context);
            return const Scaffold();
          },
        ),
      ),
    );
    TransferNotification.start(sessionId: 'tray-pending', receiving: true);
    await tester.pump();
    Future<ByteData?> requestClose() {
      final reply = Completer<ByteData?>();
      unawaited(
        messenger.handlePlatformMessage(
          HarmonyWindow.channel.name,
          const StandardMethodCodec().encodeMethodCall(const MethodCall('willClose', {'trayEnabled': true})),
          reply.complete,
        ),
      );
      return reply.future;
    }

    final first = requestClose();
    await tester.pumpAndSettle();
    expect(find.textContaining('Background transfer is not ready'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(const StandardMethodCodec().decodeEnvelope((await first)!), 'cancel');
    progress.complete();
    await tester.pumpAndSettle();
    final second = requestClose();
    await tester.pump();
    expect(const StandardMethodCodec().decodeEnvelope((await second)!), 'minimize');
    expect(find.byType(AlertDialog), findsNothing);
    TransferNotification.stop('tray-pending');
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
