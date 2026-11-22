import 'dart:convert';
import 'dart:io';

import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

final _logger = Logger('HarmonyTransferRecovery');

/// Local source files awaiting confirmation of a successful send.
/// Records contain paths and metadata, never file contents or session tokens.
class HarmonyTransferRecovery {
  static Directory? directory;
  static final _restored = <(String, String, String), List<HarmonyRecoveryItem>>{};

  static void markRestored(Iterable<HarmonyRecoveryItem> items) {
    for (final item in items) {
      final path = item.file?.path;
      final name = item.file?.name;
      final recipient = item.recipient;
      if (path != null && name != null && recipient != null) {
        _restored.putIfAbsent((path, name, recipient), () => []).add(item);
      }
    }
  }

  static void record(String sessionId, String fileId, CrossFile file, {required String recipient}) {
    final root = directory;
    final path = file.path;
    if (root == null || path == null || !p.isAbsolute(path)) return;
    try {
      final stat = File(path).statSync();
      if (stat.type != FileSystemEntityType.file || stat.size != file.size) return;
      final session = Directory(p.join(root.path, sessionId))..createSync(recursive: true);
      File(p.join(session.path, '$fileId.json')).writeAsStringSync(
        jsonEncode({
          'path': path,
          'name': file.name,
          'type': file.fileType.name,
          'size': file.size,
          'modified': stat.modified.millisecondsSinceEpoch,
          'lastModified': file.lastModified,
          'lastAccessed': file.lastAccessed,
          'recipient': recipient,
        }),
        flush: true,
      );
    } catch (error, stack) {
      _logger.warning('Could not record a recoverable send', error, stack);
    }
  }

  /// Only a confirmed send to the original recipient supersedes old records.
  static void completeFile(String sessionId, String fileId) {
    final root = directory;
    if (root == null) return;
    try {
      final record = File(p.join(root.path, sessionId, '$fileId.json'));
      if (record.existsSync()) {
        final data = jsonDecode(record.readAsStringSync()) as Map<String, dynamic>;
        final key = (data['path'] as String, data['name'] as String, data['recipient'] as String);
        for (final item in _restored.remove(key) ?? <HarmonyRecoveryItem>[]) {
          item.discard();
        }
      }
    } catch (error, stack) {
      _logger.warning('Could not clear superseded send records', error, stack);
    }
    forgetFile(sessionId, fileId);
  }

  static void forgetFile(String sessionId, String fileId) {
    final root = directory;
    if (root == null) return;
    try {
      final file = File(p.join(root.path, sessionId, '$fileId.json'));
      if (file.existsSync()) file.deleteSync();
      final session = file.parent;
      if (session.existsSync() && session.listSync().isEmpty) session.deleteSync();
    } catch (error, stack) {
      _logger.warning('Could not remove a send recovery record', error, stack);
    }
  }

  static void forgetSession(String sessionId) {
    final root = directory;
    if (root == null) return;
    try {
      final session = Directory(p.join(root.path, sessionId));
      if (session.existsSync()) session.deleteSync(recursive: true);
    } catch (error, stack) {
      _logger.warning('Could not remove send recovery records', error, stack);
    }
  }

  static List<HarmonyRecoveryItem> readPending() {
    final root = directory;
    if (root == null || !root.existsSync()) return [];
    final result = <HarmonyRecoveryItem>[];
    for (final session in root.listSync(followLinks: false).whereType<Directory>()) {
      for (final entry in session.listSync(followLinks: false).whereType<File>()) {
        if (!entry.path.endsWith('.json')) continue;
        try {
          final data = jsonDecode(entry.readAsStringSync()) as Map<String, dynamic>;
          final path = data['path'] as String;
          final stat = File(path).statSync();
          final available =
              stat.type == FileSystemEntityType.file && stat.size == data['size'] && stat.modified.millisecondsSinceEpoch == data['modified'];
          result.add(
            HarmonyRecoveryItem(
              entry,
              available
                  ? CrossFile(
                      name: data['name'] as String,
                      fileType: FileType.values.byName(data['type'] as String),
                      size: data['size'] as int,
                      thumbnail: null,
                      asset: null,
                      path: path,
                      bytes: null,
                      lastModified: data['lastModified'] as String?,
                      lastAccessed: data['lastAccessed'] as String?,
                    )
                  : null,
              data['recipient'] as String?,
              sourcePath: path,
            ),
          );
        } catch (error, stack) {
          _logger.warning('Could not read a send recovery record', error, stack);
          result.add(HarmonyRecoveryItem(entry, null, null));
        }
      }
    }
    return result;
  }
}

class HarmonyRecoveryItem {
  final File record;
  final CrossFile? file;
  final String? recipient;
  final String? sourcePath;
  HarmonyRecoveryItem(this.record, this.file, this.recipient, {this.sourcePath});

  void discard() {
    record.deleteSync();
    if (record.parent.listSync().isEmpty) record.parent.deleteSync();
  }
}
