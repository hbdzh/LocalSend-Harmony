import 'package:flutter/services.dart';

class HarmonyNotifications {
  static const _channel = MethodChannel('org.localsend.localsend_app/harmony_device');

  static Future<bool> requestPermission() async => await _channel.invokeMethod<bool>('requestNotifications') ?? false;

  static Future<void> notifyIncoming(String text) async {
    await _channel.invokeMethod<void>('notifyIncoming', {'text': text});
  }
}
