import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_notifications.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.localsend.localsend_app/harmony_device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('requests notification permission and publishes the incoming label', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'requestNotifications' ? true : null;
    });
    expect(await HarmonyNotifications.requestPermission(), isTrue);
    await HarmonyNotifications.notifyIncoming('Receiving files');
    expect(calls.map((call) => call.method), ['requestNotifications', 'notifyIncoming']);
    expect(calls.last.arguments, {'text': 'Receiving files'});
  });
}
