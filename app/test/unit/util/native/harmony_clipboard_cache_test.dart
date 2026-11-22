import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:localsend_app/util/native/harmony_clipboard_cache.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cleans removed copies only after selection and recovery stop using them', () async {
    debugHarmonyOSOverride = true;
    final temp = Directory.systemTemp.createTempSync('clipboard-cache-test-');
    final copy = Directory('${temp.path}/localsend-clipboard-file-a/folder')..createSync(recursive: true);
    final zipDir = Directory('${temp.path}/localsend-folder-zip-b')..createSync();
    final one = File('${copy.path}/one.txt')..writeAsStringSync('1');
    final two = File('${copy.path}/two.txt')..writeAsStringSync('2');
    final zip = File('${zipDir.path}/folder.zip')..writeAsStringSync('zip');
    final unrelated = File('${temp.path}/unrelated.txt')..writeAsStringSync('safe');
    HarmonyClipboardCache.register(copy.parent.path);
    HarmonyClipboardCache.register(zipDir.path);
    HarmonyTransferRecovery.directory = Directory('${temp.path}/recovery');
    addTearDown(() {
      HarmonyTransferRecovery.directory = null;
      debugHarmonyOSOverride = null;
      temp.deleteSync(recursive: true);
    });
    CrossFile selected(File file) => CrossFile(
      name: file.uri.pathSegments.last,
      fileType: FileType.other,
      size: file.lengthSync(),
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
    final ref = RefenaContainer(
      overrides: [
        globalReduxProvider.overrideWithGlobalReducer(reducer: {ClearCacheAction: null}),
      ],
    );
    final files = [selected(one), selected(two), selected(zip)];
    await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddFilesAction(files: files, converter: (file) async => file));
    HarmonyTransferRecovery.record('pending', 'file', files.last, recipient: 'recipient');
    ref.redux(selectedSendingFilesProvider).dispatch(RemoveSelectedFileAction(0));
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(copy.existsSync(), isTrue);
    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(copy.existsSync(), isFalse);
    expect(zip.existsSync(), isTrue);
    expect(unrelated.readAsStringSync(), 'safe');
    HarmonyTransferRecovery.forgetSession('pending');
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(zipDir.existsSync(), isFalse);
  });

  test('startup removes abandoned private copies and keeps recovery sources', () async {
    final temp = Directory.systemTemp.createTempSync('clipboard-restart-test-');
    final store = Directory('${temp.path}/localsend-clipboard-imports')..createSync();
    final keep = Directory('${store.path}/localsend-clipboard-file-keep/folder')..createSync(recursive: true);
    final source = File('${keep.path}/item.txt')..writeAsStringSync('original');
    final available = File('${keep.path}/available.txt')..writeAsStringSync('recoverable');
    final abandoned = Directory('${store.path}/localsend-folder-zip-old')..createSync();
    File('${abandoned.path}/folder.zip').writeAsStringSync('orphan');
    final foreign = Directory('${store.path}/other')..createSync();
    final outside = Directory('${temp.path}/outside')..createSync();
    final outsideFile = File('${outside.path}/safe.txt')..writeAsStringSync('safe');
    Link('${store.path}/localsend-clipboard-file-link').createSync(outside.path);
    HarmonyTransferRecovery.directory = Directory('${temp.path}/recovery');
    addTearDown(() {
      HarmonyTransferRecovery.directory = null;
      temp.deleteSync(recursive: true);
    });
    final recoveryFile = CrossFile(
      name: 'folder/item.txt',
      fileType: FileType.text,
      size: source.lengthSync(),
      thumbnail: null,
      asset: null,
      path: source.path,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
    HarmonyTransferRecovery.record('old-session', 'item', recoveryFile, recipient: 'device');
    HarmonyTransferRecovery.record(
      'old-session',
      'available',
      CrossFile(
        name: 'folder/available.txt',
        fileType: FileType.text,
        size: available.lengthSync(),
        thumbnail: null,
        asset: null,
        path: available.path,
        bytes: null,
        lastModified: null,
        lastAccessed: null,
      ),
      recipient: 'device',
    );
    final brokenRecord = File('${temp.path}/recovery/old-session/broken.json')..writeAsStringSync('{');
    // A changed file is unavailable for retry, but its recorded path still protects its directory.
    source.writeAsStringSync('changed contents');
    HarmonyClipboardCache.recover(store);
    await HarmonyClipboardCache.clean([]);
    expect(abandoned.existsSync(), isTrue);
    brokenRecord.deleteSync();
    HarmonyClipboardCache.recover(store);
    await HarmonyClipboardCache.clean([]);
    expect(source.existsSync(), isTrue);
    expect(HarmonyTransferRecovery.readPending().where((item) => item.file?.path == available.path), hasLength(1));
    expect(abandoned.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
    expect(outsideFile.readAsStringSync(), 'safe');
    HarmonyTransferRecovery.forgetSession('old-session');
    await HarmonyClipboardCache.clean([]);
    expect(keep.parent.existsSync(), isFalse);
    expect(outsideFile.existsSync(), isTrue);
  });

  test('only removes empty legacy clipboard directories from the mixed cache', () async {
    final cache = Directory.systemTemp.createTempSync('legacy-clipboard-test-');
    addTearDown(() => cache.deleteSync(recursive: true));
    final emptyFileCopy = Directory('${cache.path}/localsend-clipboard-file-abc123')..createSync();
    final emptyImageCopy = Directory('${cache.path}/localsend-clipboard-def456')..createSync();
    final nonempty = Directory('${cache.path}/localsend-clipboard-file-pending')..createSync();
    final source = File('${nonempty.path}/file.txt')..writeAsStringSync('keep');
    final sharedZip = Directory('${cache.path}/localsend-folder-zip-old')..createSync();
    final zip = File('${sharedZip.path}/folder.zip')..writeAsStringSync('zip contents');
    final other = Directory('${cache.path}/localsend-clipboard-imports')..createSync();
    final link = Link('${cache.path}/localsend-clipboard-file-link')..createSync(nonempty.path);
    HarmonyTransferRecovery.directory = Directory('${cache.path}/pending-sends');
    addTearDown(() => HarmonyTransferRecovery.directory = null);
    CrossFile pending(File file) => CrossFile(
      name: file.uri.pathSegments.last,
      fileType: FileType.other,
      size: file.lengthSync(),
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
    HarmonyTransferRecovery.record('old', 'file', pending(source), recipient: 'device');
    HarmonyTransferRecovery.record('old', 'zip', pending(zip), recipient: 'device');
    await cleanEmptyLegacyClipboardDirectories(cache);
    expect(emptyFileCopy.existsSync(), isFalse);
    expect(emptyImageCopy.existsSync(), isFalse);
    expect(source.readAsStringSync(), 'keep');
    expect(sharedZip.existsSync(), isTrue);
    expect(zip.readAsStringSync(), 'zip contents');
    expect(HarmonyTransferRecovery.readPending().where((item) => item.file != null), hasLength(2));
    expect(other.existsSync(), isTrue);
    expect(link.existsSync(), isTrue);
    HarmonyTransferRecovery.forgetSession('old');
    await cleanEmptyLegacyClipboardDirectories(cache);
    expect(source.readAsStringSync(), 'keep');
    expect(zip.readAsStringSync(), 'zip contents');
  });
}
