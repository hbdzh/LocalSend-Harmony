import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/util/native/harmony_empty_folder.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUp(() async => temporary = await Directory.systemTemp.createTemp('empty-folder-test-'));
  tearDown(() async => temporary.delete(recursive: true));

  test('packages an empty root directory as a ZIP containing that directory', () async {
    final root = await Directory(p.join(temporary.path, 'empty')).create();
    final zip = (await prepareHarmonyFolder(root.path, temporaryDirectory: temporary))!;
    final entries = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(p.basename(zip.path), 'empty.zip');
    expect(entries.files.map((entry) => entry.name), contains('empty/'));
    expect(entries.files.single.isFile, isFalse);
  });

  test('preserves nested empty directories and ordinary file contents', () async {
    final root = await Directory(p.join(temporary.path, 'project')).create();
    await Directory(p.join(root.path, 'nested', 'vacant')).create(recursive: true);
    await File(p.join(root.path, 'nested', 'readme.txt')).writeAsString('hello');
    final outside = await Directory(p.join(temporary.path, 'outside')).create();
    await File(p.join(outside.path, 'private.txt')).writeAsString('private');
    await Link(p.join(root.path, 'link')).create(outside.path);
    final zip = (await prepareHarmonyFolder(root.path, temporaryDirectory: temporary))!;
    final entries = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(entries.files.map((entry) => entry.name), contains('project/nested/vacant/'));
    expect(entries.files.map((entry) => entry.name), isNot(contains('project/link/private.txt')));
    expect(entries.findFile('project/nested/readme.txt')!.content, 'hello'.codeUnits);
  });

  test('keeps regular nonempty folders in the original transfer format', () async {
    final root = await Directory(p.join(temporary.path, 'ordinary')).create();
    await File(p.join(root.path, 'file.txt')).writeAsString('data');
    expect(await prepareHarmonyFolder(root.path, temporaryDirectory: temporary), isNull);
  });

  test('produces an archive accepted by the system unzip tool', () async {
    final root = await Directory(p.join(temporary.path, 'folder')).create();
    await Directory(p.join(root.path, 'empty')).create();
    await File(p.join(root.path, 'data.txt')).writeAsString('contents');
    final zip = (await prepareHarmonyFolder(root.path, temporaryDirectory: temporary))!;
    final result = await Process.run('unzip', ['-t', zip.path]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final extractPath = p.join(temporary.path, 'extract');
    final extracted = await Process.run('unzip', ['-q', zip.path, '-d', extractPath]);
    expect(extracted.exitCode, 0, reason: '${extracted.stdout}\n${extracted.stderr}');
    expect(await Directory(p.join(extractPath, 'folder', 'empty')).exists(), isTrue);
    expect(await File(p.join(extractPath, 'folder', 'data.txt')).readAsString(), 'contents');
  }, skip: !Platform.isMacOS);
}
