import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class _MetadataApi extends Fake implements RustLibApi {
  @override
  Future<FileMetadata?> crateApiMetadataReadFileMetadata({required String path}) async {
    if (path.contains('/broken/')) throw FileSystemException('read failed', path);
    return null;
  }
}

void main() {
  testWidgets('handles denied, text and image clipboard results', (tester) async {
    debugHarmonyOSOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var denied = true;
    var image = false;
    var files = false;
    final root = Directory.systemTemp.createTempSync('clipboard-test-');
    final file = File('${root.path}/clipboard.png')..writeAsBytesSync([137, 80, 78, 71]);
    final doc = File('${root.path}/report.pdf')..writeAsBytesSync([1, 2, 3]);
    final imageFile = File('${root.path}/photo.jpg')..writeAsBytesSync([4, 5]);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const clipboard = MethodChannel('org.localsend.localsend_app/harmony_clipboard');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(pathProvider, (_) async => root.path);
    messenger.setMockMethodCallHandler(clipboard, (call) async {
      if (call.method == 'read') {
        if (denied) throw PlatformException(code: '201');
        if (files) {
          return {
            'paths': [doc.path, imageFile.path],
            'failed': 1,
          };
        }
        if (image) return {'path': file.path};
        return {'text': 'hello'};
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(clipboard, null);
      messenger.setMockMethodCallHandler(pathProvider, null);
      root.deleteSync(recursive: true);
      debugHarmonyOSOverride = null;
      debugDefaultTargetPlatformOverride = null;
    });
    late BuildContext pageContext;
    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return TextButton(
                  onPressed: () => context.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: context)),
                  child: const Text('Paste'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => pageContext.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: pageContext)));
    await tester.pump();
    expect(find.textContaining('Could not read the clipboard'), findsOneWidget);
    denied = false;
    await tester.runAsync(() => pageContext.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: pageContext)));
    await tester.pump();
    expect(utf8.decode(pageContext.ref.read(selectedSendingFilesProvider).single.bytes!), 'hello');
    image = true;
    await tester.runAsync(() => pageContext.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: pageContext)));
    await tester.pumpAndSettle();
    final selected = pageContext.ref.read(selectedSendingFilesProvider);
    expect(selected.last.path, file.path);
    expect(selected.last.name, 'clipboard.png');
    expect(selected.last.size, 4);
    ScaffoldMessenger.of(pageContext).hideCurrentSnackBar();
    await tester.pumpAndSettle();
    files = true;
    await tester.runAsync(() => pageContext.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: pageContext)));
    await tester.pump();
    final imported = pageContext.ref.read(selectedSendingFilesProvider);
    expect(imported.map((item) => item.name), containsAll(['report.pdf', 'photo.jpg']));
    expect(imported.last.fileType, FileType.image);
    expect(find.textContaining('1 clipboard file(s) could not be imported'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('imports clipboard folders with relative paths and preserves empty directories in ZIP', (tester) async {
    debugHarmonyOSOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    RustLib.initMock(api: _MetadataApi());
    final root = Directory.systemTemp.createTempSync('clipboard-folders-');
    final store = '${root.path}/localsend-clipboard-imports';
    final normal = Directory('$store/localsend-clipboard-file-normal/normal/nested')..createSync(recursive: true);
    File('${normal.path}/readme.txt').writeAsStringSync('readme');
    final empty = Directory('$store/localsend-clipboard-file-zip/photos/vacant')..createSync(recursive: true);
    File('${empty.parent.path}/photo.txt').writeAsStringSync('photo');
    final broken = Directory('$store/localsend-clipboard-file-failed/broken')..createSync(recursive: true);
    File('${broken.path}/file.txt').writeAsStringSync('bad');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const clipboard = MethodChannel('org.localsend.localsend_app/harmony_clipboard');
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(
      clipboard,
      (_) async => {
        'paths': <String>[],
        'directories': [broken.path, normal.parent.path, empty.parent.path],
        'failed': 0,
      },
    );
    messenger.setMockMethodCallHandler(pathProvider, (_) async => root.path);
    addTearDown(() {
      messenger.setMockMethodCallHandler(clipboard, null);
      messenger.setMockMethodCallHandler(pathProvider, null);
      RustLib.dispose();
      root.deleteSync(recursive: true);
      debugHarmonyOSOverride = null;
      debugDefaultTargetPlatformOverride = null;
    });
    late BuildContext pageContext;
    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => pageContext.global.dispatchAsync(PickFileAction(option: FilePickerOption.clipboard, context: pageContext)));
    await tester.pump();
    final selected = pageContext.ref.read(selectedSendingFilesProvider);
    expect(selected.map((file) => file.name), contains('normal/nested/readme.txt'));
    final zip = selected.singleWhere((file) => file.name == 'photos.zip');
    final entries = ZipDecoder().decodeBytes(File(zip.path!).readAsBytesSync()).files.map((file) => file.name);
    expect(entries, containsAll(['photos/vacant/', 'photos/photo.txt']));
    expect(find.textContaining('packed as ZIP'), findsOneWidget);
    expect(find.textContaining('1 clipboard file(s) could not be imported'), findsOneWidget);
    expect(broken.parent.existsSync(), isFalse);
    expect(empty.parent.parent.existsSync(), isFalse);
    expect(normal.existsSync(), isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cancelling the system file picker keeps the current page open', (tester) async {
    debugHarmonyOSOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    const fileChannel = MethodChannel('plugins.flutter.io/file_selector');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(fileChannel, (_) async => <String>[]);
    addTearDown(() {
      messenger.setMockMethodCallHandler(fileChannel, null);
      debugHarmonyOSOverride = null;
      debugDefaultTargetPlatformOverride = null;
    });
    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          navigatorKey: Routerino.navigatorKey,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (pageContext) => TextButton(
                        onPressed: () => pageContext.global.dispatchAsync(PickFileAction(option: FilePickerOption.file, context: pageContext)),
                        child: const Text('Pick files'),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Open page'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pick files'));
    await tester.pumpAndSettle();
    expect(find.text('Pick files'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
