import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:localsend_isolates/src/task/server/file_saver.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUpAll(() {
    RustLib.initMock(api: _MockRustLibApi());
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_saver_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<String> digest(String parentDirectory, String fileName) async {
    final (path, _, _) = await digestFilePathAndPrepareDirectory(
      parentDirectory: parentDirectory,
      fileName: fileName,
      createdDirectories: {},
    );
    return path;
  }

  test('creates the destination directory when it does not exist', () async {
    final destination = p.join(tempDir.path, 'gone');
    final path = await digest(destination, 'file.txt');

    expect(Directory(destination).existsSync(), isTrue);
    expect(path, p.join(destination, 'file.txt'));
  });

  test('creates the sub-directories of a folder transfer', () async {
    final path = await digest(tempDir.path, p.join('outer', 'inner', 'file.txt'));

    expect(Directory(p.join(tempDir.path, 'outer', 'inner')).existsSync(), isTrue);
    expect(path, p.join(tempDir.path, 'outer', 'inner', 'file.txt'));
  });

  test('keeps an existing directory and its content', () async {
    File(p.join(tempDir.path, 'file.txt')).writeAsStringSync('hello');

    final path = await digest(tempDir.path, 'file.txt');

    expect(path, p.join(tempDir.path, 'file (2).txt'));
    expect(File(p.join(tempDir.path, 'file.txt')).readAsStringSync(), 'hello');
  });

  test('creates distinct names when another receive claims the first candidate', () async {
    final original = File(p.join(tempDir.path, 'file.txt'))..writeAsStringSync('keep');
    var nextFd = 100;
    int createExclusive(String path) {
      try {
        File(path).createSync(exclusive: true);
        return nextFd++;
      } on FileSystemException {
        return -17;
      }
    }

    final targets = await Future.wait(
      List.generate(
        2,
        (_) => prepareHarmonyFileSaveTarget(
          parentDirectory: tempDir.path,
          fileName: 'file.txt',
          createdDirectories: {},
          openExclusive: createExclusive,
        ),
      ),
    );
    expect(targets.map((target) => target.displayPath).toSet(), {p.join(tempDir.path, 'file (2).txt'), p.join(tempDir.path, 'file (3).txt')});
    expect(targets.map((target) => target.fileDescriptor).toSet(), {100, 101});
    expect(original.readAsStringSync(), 'keep');
  });

  test('does not follow a folder link outside the selected directory', () async {
    final outside = await Directory.systemTemp.createTemp('receive-outside-');
    addTearDown(() => outside.delete(recursive: true));
    Link(p.join(tempDir.path, 'link')).createSync(outside.path);
    await expectLater(
      digestFilePathAndPrepareDirectory(
        parentDirectory: tempDir.path,
        fileName: 'link/file.txt',
        createdDirectories: {},
        rejectLinks: true,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File(p.join(outside.path, 'file.txt')).exists(), isFalse);
  });

  test('still rejects path traversal', () async {
    await expectLater(
      digest(tempDir.path, p.join('..', 'escaped', 'file.txt')),
      throwsA('Path traversal detected'),
    );
  });

  test('saves under an alternative name when a directory occupies the incoming name', () async {
    final existingDirectory = Directory(p.join(tempDir.path, 'file.txt'))..createSync();
    final existingContent = File(p.join(existingDirectory.path, 'keep.txt'))..writeAsStringSync('keep');
    final existingFile = File(p.join(tempDir.path, 'file (2).txt'))..writeAsStringSync('existing');

    final path = await digest(tempDir.path, 'file.txt');
    await File(path).writeAsString('received');

    expect(path, p.join(tempDir.path, 'file (3).txt'));
    expect(File(path).readAsStringSync(), 'received');
    expect(existingContent.readAsStringSync(), 'keep');
    expect(existingFile.readAsStringSync(), 'existing');
  });
}

/// The sanitizer lives in the Rust library, which is not loaded in unit tests.
class _MockRustLibApi implements RustLibApi {
  @override
  String crateApiFilenameSanitizeFileName({required String name}) => name;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Not mocked: ${invocation.memberName}');
}
