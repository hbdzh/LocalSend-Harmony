import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _MetadataApi extends Fake implements RustLibApi {
  @override
  Future<FileMetadata?> crateApiMetadataReadFileMetadata({required String path}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports nested files with relative paths and does not follow links', () async {
    final temp = await Directory.systemTemp.createTemp('localsend-folder-test-');
    addTearDown(() async => temp.delete(recursive: true));
    final root = Directory('${temp.path}/photos');
    final nested = Directory('${root.path}/nested');
    await nested.create(recursive: true);
    await File('${root.path}/first.txt').writeAsString('first');
    await File('${nested.path}/second.txt').writeAsString('second');
    final external = Directory('${temp.path}/outside');
    await external.create();
    await File('${external.path}/private.txt').writeAsString('private');
    await Link('${root.path}/link').create(external.path);

    RustLib.initMock(api: _MetadataApi());
    addTearDown(RustLib.dispose);
    final service = ReduxNotifier.test(redux: SelectedSendingFilesNotifier());
    await service.dispatchAsync(AddDirectoryAction(root.path, followLinks: false));
    expect(service.state.map((file) => file.name).toSet(), {'photos/first.txt', 'photos/nested/second.txt'});
  });
}
