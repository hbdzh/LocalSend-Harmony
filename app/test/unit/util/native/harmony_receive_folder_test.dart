import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_receive_folder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.localsend.localsend_app/harmony_device');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('persists a writable choice, activates it, and reports revoked access', () async {
    final folder = await Directory.systemTemp.createTemp('receive-folder-test-');
    addTearDown(() => folder.delete(recursive: true));
    var denied = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'chooseReceiveFolder') return {'uri': 'file://docs/folder', 'path': folder.path};
      if (call.method == 'revokeReceiveFolder' && denied) throw PlatformException(code: 'already_revoked');
      if (call.method == 'activateReceiveFolder') {
        if (denied) throw PlatformException(code: 'receive_folder_failed');
        expect((call.arguments as Map)['uri'], 'file://docs/folder');
        return folder.path;
      }
      return null;
    });
    expect(await chooseHarmonyReceiveFolder(), 'file://docs/folder');
    expect(await resolveHarmonyReceiveFolder(), folder.path);
    denied = true;
    await expectLater(resolveHarmonyReceiveFolder(), throwsA(isA<PlatformException>()));
    await clearHarmonyReceiveFolder();
    expect(await resolveHarmonyReceiveFolder(), isNull);
  });

  test('does not store a folder that cannot be written', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => {'uri': 'file://docs/missing', 'path': '/missing-localsend-test-dir'});
    await expectLater(chooseHarmonyReceiveFolder(), throwsA(isA<FileSystemException>()));
    expect(await getHarmonyReceiveFolder(), isNull);
  });
}
