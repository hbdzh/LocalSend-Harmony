import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('org.localsend.localsend_app/harmony_device');
const _key = 'harmony_receive_folder_uri';

Future<String?> getHarmonyReceiveFolder() async => (await SharedPreferences.getInstance()).getString(_key);

/// Persist the system URI, but only after its sandbox path has passed a write check.
Future<String?> chooseHarmonyReceiveFolder() async {
  final selected = await _channel.invokeMapMethod<String, String>('chooseReceiveFolder');
  if (selected == null) return null;
  final uri = selected['uri']!;
  final path = selected['path']!;
  final probe = await Directory(path).createTemp('.localsend-write-check-');
  await probe.delete();
  await (await SharedPreferences.getInstance()).setString(_key, uri);
  return uri;
}

/// Called before every incoming session, including after an app restart.
Future<String?> resolveHarmonyReceiveFolder() async {
  final uri = await getHarmonyReceiveFolder();
  if (uri == null) return null;
  final path = await _channel.invokeMethod<String>('activateReceiveFolder', {'uri': uri});
  if (path == null || path.isEmpty) throw StateError('Receive folder path is unavailable');
  return path;
}

Future<void> clearHarmonyReceiveFolder() async {
  final uri = await getHarmonyReceiveFolder();
  if (uri != null) {
    try {
      await _channel.invokeMethod<void>('revokeReceiveFolder', {'uri': uri});
    } on PlatformException catch (error, stack) {
      // Already-revoked permissions must not prevent resetting the preference.
      Logger('HarmonyReceiveFolder').warning('Could not revoke folder access', error, stack);
    }
  }
  await (await SharedPreferences.getInstance()).remove(_key);
}
