import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Returns a ZIP when a dropped directory contains an empty directory.
/// ZIP is used because the LocalSend protocol has no directory-only entry.
Future<File?> prepareHarmonyFolder(String directoryPath, {Directory? temporaryDirectory}) async {
  final root = Directory(directoryPath);
  final directories = <String>{p.normalize(root.path)};
  final nonEmpty = <String>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File && entity is! Directory) continue;
    nonEmpty.add(p.normalize(p.dirname(entity.path)));
    if (entity is Directory) directories.add(p.normalize(entity.path));
  }
  if (directories.difference(nonEmpty).isEmpty) return null;

  final temp = await (temporaryDirectory ?? await getTemporaryDirectory()).createTemp('localsend-folder-zip-');
  final zipPath = p.join(temp.path, '${p.basename(root.path)}.zip');
  final rootPath = root.path;
  try {
    await Isolate.run(() => _writeFolderZip(rootPath, zipPath));
    return File(zipPath);
  } catch (_) {
    await temp.delete(recursive: true);
    rethrow;
  }
}

/// Uses stored entries and file streams to avoid buffering large files in RAM.
Future<void> _writeFolderZip(String folderPath, String zipPath) async {
  final root = Directory(folderPath);
  final rootName = p.basename(root.path);
  final zip = ZipFileEncoder();
  zip.create(zipPath);
  try {
    zip.addArchiveFile(ArchiveFile.directory(rootName)..compression = CompressionType.none);
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relative = p.relative(entity.path, from: root.path).replaceAll('\\', '/');
      final entryName = '$rootName/$relative';
      if (entity is Directory) {
        zip.addArchiveFile(ArchiveFile.directory(entryName)..compression = CompressionType.none);
      } else if (entity is File) {
        final input = InputFileStream(entity.path);
        try {
          final entry = ArchiveFile.stream(entryName, input)..compression = CompressionType.none;
          zip.addArchiveFile(entry);
        } finally {
          await input.close();
        }
      }
    }
  } finally {
    await zip.close();
  }
}
