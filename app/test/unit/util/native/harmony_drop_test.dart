import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_drop.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();

  Future<Object?> send(MethodCall call) async {
    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(HarmonyDrop.channel.name, codec.encodeMethodCall(call), reply.complete);
    final data = await reply.future;
    return data == null ? null : codec.decodeEnvelope(data);
  }

  int? listener;
  tearDown(() {
    if (listener != null) HarmonyDrop.dispose(listener!);
  });

  test('forwards drag events and acknowledges imported files', () async {
    var entered = 0;
    var exited = 0;
    listener = HarmonyDrop.listen(
      onEntered: () => entered++,
      onExited: () => exited++,
      onDropped: (paths, directories, failed) async {
        expect(directories, isEmpty);
        expect(paths, ['/cache/one.txt', '/cache/two.txt']);
        expect(failed, 1);
        return true;
      },
    );
    await send(const MethodCall('entered'));
    await send(const MethodCall('exited'));
    final result = await send(
      const MethodCall('dropped', {
        'paths': ['/cache/one.txt', '/cache/two.txt'],
        'failed': 1,
      }),
    );
    expect(entered, 1);
    expect(exited, 1);
    expect(result, true);
  });

  test('forwards dropped directory roots alongside files', () async {
    listener = HarmonyDrop.listen(
      onEntered: () {},
      onExited: () {},
      onDropped: (paths, directories, failed) async {
        expect(paths, ['/cache/drop/single.txt']);
        expect(directories, ['/cache/drop/photos']);
        expect(failed, 0);
        return true;
      },
    );
    expect(
      await send(
        const MethodCall('dropped', {
          'paths': ['/cache/drop/single.txt'],
          'directories': ['/cache/drop/photos'],
          'failed': 0,
        }),
      ),
      true,
    );
  });

  test('reports a rejected drop so native temporary files can be removed', () async {
    listener = HarmonyDrop.listen(onEntered: () {}, onExited: () {}, onDropped: (_, _, _) async => false);
    expect(
      await send(
        const MethodCall('dropped', {
          'paths': ['/cache/one.txt'],
          'failed': 0,
        }),
      ),
      false,
    );
  });

  test('disposing an older page does not remove the current listener', () async {
    final old = HarmonyDrop.listen(onEntered: () {}, onExited: () {}, onDropped: (_, _, _) async => false);
    listener = HarmonyDrop.listen(onEntered: () {}, onExited: () {}, onDropped: (_, _, _) async => true);
    HarmonyDrop.dispose(old);
    expect(await send(const MethodCall('dropped', {'paths': <String>[], 'failed': 0})), true);
  });
}
