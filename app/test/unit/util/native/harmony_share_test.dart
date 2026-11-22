import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/harmony_share.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../../mocks.mocks.dart';

class _MetadataApi extends Fake implements RustLibApi {
  @override
  Future<FileMetadata?> crateApiMetadataReadFileMetadata({required String path}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  test('imports shared file and text after Dart registers its receiver', () async {
    final dir = await Directory.systemTemp.createTemp('harmony-share-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/shared.txt').writeAsString('contents');
    RustLib.initMock(api: _MetadataApi());
    addTearDown(RustLib.dispose);
    final ref = RefenaContainer();
    addTearDown(ref.disposeContainer);
    var ready = false;
    messenger.setMockMethodCallHandler(HarmonyShare.channel, (call) async {
      ready = call.method == 'ready';
      return null;
    });
    addTearDown(() {
      HarmonyShare.channel.setMethodCallHandler(null);
      messenger.setMockMethodCallHandler(HarmonyShare.channel, null);
    });
    await HarmonyShare.start(ref);
    expect(ready, isTrue);
    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      HarmonyShare.channel.name,
      codec.encodeMethodCall(
        MethodCall('received', {
          'paths': [file.path],
          'texts': ['shared text'],
          'failed': 0,
        }),
      ),
      reply.complete,
    );
    expect(codec.decodeEnvelope((await reply.future)!), isTrue);
    final selection = ref.read(selectedSendingFilesProvider);
    expect(selection.length, 2);
    expect(selection.first.path, file.path);
    expect(selection.last.bytes, 'shared text'.codeUnits);
  });

  test('stores PC tap files in receive history, not the sending selection', () async {
    final dir = await Directory.systemTemp.createTemp('harmony-knock-test-');
    addTearDown(() => dir.delete(recursive: true));
    final file = await File('${dir.path}/received.txt').writeAsString('hello');
    final persistence = MockPersistenceService();
    when(persistence.isSaveToHistory()).thenReturn(true);
    final ref = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    addTearDown(ref.disposeContainer);
    messenger.setMockMethodCallHandler(HarmonyShare.channel, (call) async => null);
    addTearDown(() {
      HarmonyShare.channel.setMethodCallHandler(null);
      messenger.setMockMethodCallHandler(HarmonyShare.channel, null);
    });
    await HarmonyShare.start(ref);
    final reply = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      HarmonyShare.channel.name,
      codec.encodeMethodCall(
        MethodCall('received', {
          'kind': 'knock',
          'paths': ['${dir.path}/missing.txt', file.path],
          'texts': <String>[],
          'failed': 0,
        }),
      ),
      reply.complete,
    );
    expect(codec.decodeEnvelope((await reply.future)!), isTrue);
    expect(ref.read(receiveHistoryProvider).single.path, file.path);
    expect(ref.read(receiveHistoryProvider).single.fileSize, 5);
    expect(ref.read(selectedSendingFilesProvider), isEmpty);
  });

  test('lists stored tap files independently of history', () async {
    messenger.setMockMethodCallHandler(HarmonyShare.channel, (call) async {
      expect(call.method, 'listKnockFiles');
      return {
        'paths': ['/private/z.txt', '/private/a.txt'],
        'failed': 0,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(HarmonyShare.channel, null));
    expect(await HarmonyShare.listReceivedKnockFiles(), ['/private/a.txt', '/private/z.txt']);
  });

  testWidgets('requires confirmation before deleting an interrupted file', (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(HarmonyShare.channel, (call) async {
      calls.add(call);
      if (call.method == 'listKnockFiles') return {'paths': <String>[], 'failed': 1};
      if (call.method == 'listPendingKnockFiles') {
        return {
          'paths': ['/private/partial.txt'],
          'failed': 0,
        };
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(HarmonyShare.channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => HarmonyShare.openReceivedKnockFiles(context), child: const Text('Open')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Possibly incomplete'), findsOneWidget);
    expect(find.text('1 files or folders could not be read'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'deletePendingKnockFile'), isEmpty);
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.method == 'deletePendingKnockFile').length, 1);
    expect(find.text('partial.txt'), findsNothing);
  });

  testWidgets('arms tap sharing with the exact selection and disarms on close', (tester) async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(HarmonyShare.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(HarmonyShare.channel, null));
    const selection = [
      CrossFile(
        name: 'message.txt',
        fileType: FileType.text,
        size: 2,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: [104, 105],
        lastModified: null,
        lastAccessed: null,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => HarmonyShare.shareSelection(context, selection, knock: true), child: const Text('Start')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(calls.first.method, 'armKnock');
    expect((calls.first.arguments as Map)['texts'], ['hi']);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)));
    await tester.pumpAndSettle();
    expect(calls.last.method, 'disarmKnock');
  });
}
