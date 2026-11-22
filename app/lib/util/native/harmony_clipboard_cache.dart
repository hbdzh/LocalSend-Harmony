import 'dart:io';

import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('HarmonyClipboardCache');
final _legacyImageDirectory = RegExp(r'^localsend-clipboard-(?:XXXXXX)?[A-Za-z0-9]{6}$');

/// Old imports shared the cache with other features and had no ownership marker.
/// Only remove empty clipboard directories; ZIP directories are shared and
/// nonempty copies may still be needed by a recovery record.
Future<void> cleanEmptyLegacyClipboardDirectories(Directory cache) async {
  if (!await cache.exists()) return;
  await for (final entry in cache.list(followLinks: false)) {
    if (entry is! Directory) continue;
    final name = p.basename(entry.path);
    if (!name.startsWith('localsend-clipboard-file-') && !_legacyImageDirectory.hasMatch(name)) continue;
    try {
      if (await entry.list(followLinks: false).isEmpty) {
        await entry.delete(); // Dart's nonrecursive delete only removes an empty directory.
      }
    } on FileSystemException catch (error) {
      _logger.warning('Could not remove empty legacy clipboard directory', error);
    }
  }
}

/// Tracks the private directories created for clipboard imports.
class HarmonyClipboardCache {
  static const storeName = 'localsend-clipboard-imports';
  static final _owned = <String>{};
  static final _pending = <String>{};
  static final _inFlight = <String, int>{};

  static Future<Directory> store() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, storeName));
    await directory.create(recursive: true);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) != FileSystemEntityType.directory) {
      throw FileSystemException('Clipboard cache is not a directory', directory.path);
    }
    return directory;
  }

  /// Called once before the app starts accepting clipboard imports.
  static void recover(Directory store) {
    if (HarmonyTransferRecovery.directory == null || FileSystemEntity.typeSync(store.path, followLinks: false) != FileSystemEntityType.directory) {
      return;
    }
    for (final entry in store.listSync(followLinks: false).whereType<Directory>()) {
      final name = p.basename(entry.path);
      if (name.startsWith('localsend-clipboard-') || name.startsWith('localsend-folder-zip-')) {
        register(entry.path);
        _pending.add(p.normalize(entry.path));
      }
    }
  }

  static void register(String directory) => _owned.add(p.normalize(directory));

  static void forget(String directory) {
    _owned.remove(p.normalize(directory));
    _pending.remove(p.normalize(directory));
  }

  static void defer(Iterable<String?> paths) {
    for (final root in _owned) {
      if (paths.whereType<String>().any((path) => p.isWithin(root, p.normalize(path)))) _pending.add(root);
    }
  }

  static void retain(Iterable<String?> paths) {
    for (final path in paths.whereType<String>()) {
      _inFlight[path] = (_inFlight[path] ?? 0) + 1;
    }
  }

  static void release(Iterable<String?> paths) {
    for (final path in paths.whereType<String>()) {
      final count = _inFlight[path];
      if (count == 1) {
        _inFlight.remove(path);
      } else if (count != null) {
        _inFlight[path] = count - 1;
      }
    }
  }

  static Future<void> clean(Iterable<String?> references) async {
    if (_pending.isEmpty || HarmonyTransferRecovery.directory == null) return;
    final List<HarmonyRecoveryItem> pendingRecovery;
    try {
      pendingRecovery = HarmonyTransferRecovery.readPending();
    } catch (error, stack) {
      _logger.warning('Could not inspect send recovery records', error, stack);
      return;
    }
    // An unreadable recovery record may still refer to one of these directories.
    if (pendingRecovery.any((item) => item.sourcePath == null)) return;
    final paths = [
      ...references.whereType<String>(),
      ..._inFlight.keys,
      ...pendingRecovery.map((item) => item.sourcePath!),
    ];
    final discarded = <Directory>[];
    for (final root in _pending.toList()) {
      if (paths.any((path) => p.isWithin(root, p.normalize(path)))) continue;
      try {
        final dir = Directory(root);
        if (dir.existsSync()) {
          // Rename synchronously after checking references; recursive deletion can
          // then run asynchronously without racing a new user of the old path.
          final trash = dir.parent.createTempSync('localsend-clipboard-trash-');
          try {
            dir.renameSync(p.join(trash.path, 'contents'));
            discarded.add(trash);
          } catch (_) {
            trash.deleteSync();
            rethrow;
          }
        }
        _pending.remove(root);
        _owned.remove(root);
      } catch (error, stack) {
        _logger.warning('Could not remove clipboard cache directory', error, stack);
      }
    }
    await Future.wait(
      discarded.map((directory) async {
        try {
          await directory.delete(recursive: true);
        } catch (error, stack) {
          _logger.warning('Could not remove clipboard cache directory', error, stack);
        }
      }),
    );
  }
}

class CleanHarmonyClipboardCacheAction extends AsyncGlobalAction {
  @override
  Future<void> reduce() async {
    final paths = <String?>[
      ...ref.read(selectedSendingFilesProvider).map((file) => file.path),
      for (final session in ref.read(sendProvider).values) ...session.files.values.map((file) => file.path),
    ];
    await HarmonyClipboardCache.clean(paths);
  }
}

class CleanLegacyHarmonyClipboardCacheAction extends AsyncGlobalAction {
  @override
  Future<void> reduce() async {
    try {
      await cleanEmptyLegacyClipboardDirectories(await getTemporaryDirectory());
    } catch (error, stack) {
      _logger.warning('Could not inspect legacy clipboard cache', error, stack);
    }
  }
}
