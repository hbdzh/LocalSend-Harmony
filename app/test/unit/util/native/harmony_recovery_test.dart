import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/util/harmony_receive_recovery.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('localsend-recovery-test-');
    HarmonyTransferRecovery.directory = Directory('${root.path}/sends');
  });
  tearDown(() {
    HarmonyTransferRecovery.directory = null;
    root.deleteSync(recursive: true);
  });

  test('only unchanged unfinished files can be restored after restart', () {
    final first = File('${root.path}/first')..writeAsStringSync('one');
    final second = File('${root.path}/second')..writeAsStringSync('two');
    CrossFile source(File file) => CrossFile(
      name: 'folder/${file.uri.pathSegments.last}',
      fileType: FileType.other,
      size: 3,
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
    HarmonyTransferRecovery.record('session', 'first', source(first), recipient: 'peer-a');
    HarmonyTransferRecovery.record('session', 'second', source(second), recipient: 'peer-a');
    HarmonyTransferRecovery.forgetFile('session', 'first');
    HarmonyTransferRecovery.directory = null;
    HarmonyTransferRecovery.directory = Directory('${root.path}/sends');
    var pending = HarmonyTransferRecovery.readPending();
    expect(pending.single.file?.name, 'folder/second');
    HarmonyTransferRecovery.markRestored(pending);
    expect(HarmonyTransferRecovery.readPending(), hasLength(1));
    HarmonyTransferRecovery.record('cancelled', 'second', source(second), recipient: 'peer-a');
    HarmonyTransferRecovery.forgetSession('cancelled');
    expect(HarmonyTransferRecovery.readPending(), hasLength(1));
    HarmonyTransferRecovery.record('other-peer', 'second', source(second), recipient: 'peer-b');
    HarmonyTransferRecovery.completeFile('other-peer', 'second');
    expect(HarmonyTransferRecovery.readPending(), hasLength(1));
    HarmonyTransferRecovery.record('new-session', 'second', source(second), recipient: 'peer-a');
    HarmonyTransferRecovery.completeFile('new-session', 'second');
    expect(HarmonyTransferRecovery.readPending(), isEmpty);
    HarmonyTransferRecovery.record('later', 'second', source(second), recipient: 'peer-a');
    second.writeAsStringSync('changed');
    pending = HarmonyTransferRecovery.readPending();
    expect(pending.single.file, isNull);
    pending.single.discard();
    expect(HarmonyTransferRecovery.readPending(), isEmpty);
    expect(second.readAsStringSync(), 'changed');
  });

  test('receive records never remove a replaced or completed file', () {
    final target = File('${root.path}/received')..writeAsStringSync('partial');
    final marker = HarmonyReceiveRecovery.record(root.path, target.path);
    expect(HarmonyReceiveRecovery.pending(root.path), isEmpty);
    expect(HarmonyReceiveRecovery.pending(root.path, includeActive: true), hasLength(1));
    final interrupted = HarmonyReceiveRecovery.markFailed(marker);
    target.deleteSync();
    target.writeAsStringSync('replacement');
    expect(HarmonyReceiveRecovery.pending(root.path).single.$2, target.path);
    HarmonyReceiveRecovery.forget(interrupted);
    expect(HarmonyReceiveRecovery.pending(root.path), isEmpty);
    expect(target.readAsStringSync(), 'replacement');
  });
}
