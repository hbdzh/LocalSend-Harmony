import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('keeps one Harmony task while aggregating concurrent transfers', (tester) async {
    final calls = <MethodCall>[];
    const channel = MethodChannel('org.localsend.localsend_app/harmony_background');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
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
      TransferNotification.harmonyOverride = null;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    TransferNotification.start(sessionId: 'a', receiving: false);
    TransferNotification.update(sessionId: 'a', currentBytes: 50, totalBytes: 100, startTime: null, endTime: null);
    TransferNotification.start(sessionId: 'b', receiving: true);
    expect(TransferNotification.shouldUpdateSession('a'), isFalse);
    expect(TransferNotification.shouldUpdateSession('b'), isTrue);
    TransferNotification.update(sessionId: 'b', currentBytes: 100, totalBytes: 200, startTime: null, endTime: null);
    TransferNotification.stop('a');
    TransferNotification.stop('b');
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'start').length, 1);
    expect(calls.where((call) => call.method == 'stop').length, 1);
    final progress = calls.where((call) => call.method == 'progress').toList();
    expect(progress.any((call) => (call.arguments as Map)['progress'] == 50), isTrue);
    expect((progress.last.arguments as Map)['title'], 'Receiving');
    expect(calls.last.method, 'stop');
    expect(TransferNotification.shouldUpdateSession('b'), isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('serializes a delayed start, progress and final stop', (tester) async {
    final start = Completer<void>();
    final calls = <String>[];
    const channel = MethodChannel('org.localsend.localsend_app/harmony_background');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') await start.future;
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
      TransferNotification.harmonyOverride = null;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    TransferNotification.start(sessionId: 'delayed', receiving: false);
    TransferNotification.update(sessionId: 'delayed', currentBytes: 20, totalBytes: 100, startTime: null, endTime: null);
    TransferNotification.stop('delayed');
    await tester.pump();
    expect(calls, ['start']);
    start.complete();
    await tester.pumpAndSettle();
    expect(calls, ['start', 'progress', 'progress', 'stop']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reports a failed start and still sends the final stop', (tester) async {
    final calls = <String>[];
    const channel = MethodChannel('org.localsend.localsend_app/harmony_background');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') throw PlatformException(code: 'denied');
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
      TransferNotification.harmonyOverride = null;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    TransferNotification.start(sessionId: 'failed', receiving: false);
    await tester.pumpAndSettle();
    expect(TransferNotification.harmonyBackgroundUnavailable.value, isTrue);
    TransferNotification.update(sessionId: 'failed', currentBytes: 1, totalBytes: 10, startTime: null, endTime: null);
    TransferNotification.stop('failed');
    await tester.pumpAndSettle();
    expect(calls, ['start', 'stop']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a new transfer is not marked ready while its start is queued', (tester) async {
    final stop = Completer<void>();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.localsend.localsend_app/harmony_background');
    var stops = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stop' && ++stops == 1) await stop.future;
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
      TransferNotification.harmonyOverride = null;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    TransferNotification.start(sessionId: 'first', receiving: true);
    await tester.pumpAndSettle();
    expect(TransferNotification.harmonyBackgroundReady, isTrue);
    TransferNotification.stop('first');
    TransferNotification.start(sessionId: 'second', receiving: false);
    await tester.pump();
    expect(TransferNotification.harmonyBackgroundReady, isFalse);
    stop.complete();
    await tester.pumpAndSettle();
    expect(TransferNotification.harmonyBackgroundReady, isTrue);
    TransferNotification.stop('second');
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cancellation during a progress update warns until the user retries', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('org.localsend.localsend_app/harmony_background');
    final delayed = Completer<void>();
    var progressCalls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'progress' && ++progressCalls == 2) await delayed.future;
      return null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    TransferNotification.harmonyOverride = true;
    TransferNotification.init(NotificationStrings(
      titleReceiving: 'Receiving', titleSending: 'Sending',
      remainingTimeMinutes: ({required m, required ss}) => '$m:$ss',
      remainingTimeLong: ({required h, required m}) => '$h:$m',
    ));
    addTearDown(() {
      TransferNotification.harmonyOverride = null;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(channel, null);
    });
    TransferNotification.start(sessionId: 'cancelled', receiving: true);
    await tester.pumpAndSettle();
    TransferNotification.update(sessionId: 'cancelled', currentBytes: 1, totalBytes: 10, startTime: null, endTime: null);
    await tester.pump();
    await messenger.handlePlatformMessage(channel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('cancelled')), (_) {});
    expect(TransferNotification.harmonyBackgroundUnavailable.value, isTrue);
    delayed.complete();
    await tester.pumpAndSettle();
    expect(TransferNotification.harmonyBackgroundReady, isFalse);
    TransferNotification.retryHarmonyBackground();
    await tester.pumpAndSettle();
    expect(TransferNotification.harmonyBackgroundReady, isTrue);
    TransferNotification.stop('cancelled');
    await tester.pumpAndSettle();
    debugDefaultTargetPlatformOverride = null;
  });
}
