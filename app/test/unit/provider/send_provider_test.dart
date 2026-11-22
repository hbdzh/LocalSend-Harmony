import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:localsend_app/util/native/harmony_clipboard_cache.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart';
import 'package:localsend_isolates/rust/api/model.dart' show PrepareUploadRequestDto, PrepareUploadResponseDto, ProtocolType;
import 'package:localsend_isolates/rust/frb_generated.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';

class _SyncState extends Fake implements SyncState {}

class _Isolate extends Fake implements IsolateController {}

class _Favorites extends Fake implements FavoritesService {}

class _Logs extends Fake implements DiscoveryLogger {}

class _Nearby extends NearbyDevicesService {
  final Device device;
  _Nearby(this.device) : super(isolateController: _Isolate(), favoriteService: _Favorites(), discoveryLogs: _Logs());
  @override
  NearbyDevicesState init() =>
      NearbyDevicesState(runningFavoriteScan: false, runningIps: {}, devices: {device.fingerprint: device}, signalingDevices: {});
}

class _RetrySender extends SendNotifier {
  final SendSessionState session;
  List<CrossFile>? retried;
  Device? retryTarget;
  _RetrySender(this.session);
  @override
  Map<String, SendSessionState> init() => {session.sessionId: session};
  @override
  Future<void> startSession({required Device target, required List<CrossFile> files, required bool background}) async {
    retryTarget = target;
    retried = files;
  }
}

class _Settings extends Fake implements SettingsState {
  @override
  bool get createChecksums => false;
  @override
  SendMode get sendMode => SendMode.single;
}

class _TestSettingsService extends SettingsService {
  _TestSettingsService(super.persistence);

  @override
  SettingsState init() => _Settings();
}

class _CancellationToken extends Fake implements RsCancellationToken {
  @override
  void cancel() {}
}

class _RustLibApi extends Fake implements RustLibApi {
  @override
  RsCancellationToken crateApiCancelCreateCancellationToken() => _CancellationToken();
}

/// A client whose prepare-upload request is answered by the test.
class _HttpClient extends Fake implements RsHttpClient {
  final prepareUploadResponse = Completer<PrepareUploadResult>();
  final prepareUploadCalled = Completer<void>();
  final canceledSessions = <String>[];

  @override
  Future<PrepareUploadResult> prepareUpload({
    required ProtocolType protocol,
    required String ip,
    required int port,
    required PrepareUploadRequestDto payload,
    String? publicKey,
    String? pin,
    required RsCancellationToken cancelToken,
  }) {
    prepareUploadCalled.complete();
    return prepareUploadResponse.future;
  }

  @override
  Future<void> cancel({required ProtocolType protocol, required String ip, required int port, required String sessionId}) async {
    canceledSessions.add(sessionId);
  }
}

class _HttpClientCollection extends Fake implements HttpClientCollection {
  final RsHttpClient client;

  _HttpClientCollection(this.client);

  @override
  RsHttpClient pinnedTo(String fingerprint) => client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    RustLib.initMock(api: _RustLibApi());
  });

  test('resends only failed files in a new session using the latest device address', () async {
    final original = _createDevice(fingerprint: 'target');
    final latest = original.copyWith(ip: '192.168.1.8');
    SendingFile file(String id) => SendingFile(
      file: FileDto(
        id: id,
        fileName: '$id.txt',
        size: 3,
        fileType: FileType.text,
        hash: null,
        preview: null,
        metadata: const FileMetadata(lastModified: '2025-01-01T00:00:00Z', lastAccessed: null),
      ),
      token: 'expired',
      thumbnail: null,
      asset: null,
      path: '/files/$id.txt',
      bytes: null,
      errorMessage: null,
    );
    final sender = _RetrySender(
      SendSessionState(
        sessionId: 'old',
        remoteSessionId: 'expired',
        background: false,
        status: SessionStatus.finishedWithErrors,
        target: original,
        files: {'ok': file('ok'), 'failed': file('failed')},
        hashedFileCount: 2,
        startTime: null,
        endTime: null,
        sendingTasks: [],
        errorMessage: null,
      ),
    );
    final transfers = FileTransferNotifier()..setStatuses(sessionId: 'old', statuses: {'ok': FileStatus.finished, 'failed': FileStatus.failed});
    final client = _HttpClient();
    final ref = RefenaContainer(
      overrides: [
        sendProvider.overrideWithNotifier((_) => sender),
        nearbyDevicesProvider.overrideWithNotifier((_) => _Nearby(latest)),
        fileTransferProvider.overrideWithNotifier((_) => transfers),
        httpProvider.overrideWithBuilder((_) => _HttpClientCollection(client)),
      ],
    );
    await ref.notifier(sendProvider).retryFailedFiles('old');
    expect(sender.retryTarget?.ip, '192.168.1.8');
    expect(client.canceledSessions, ['expired']);
    expect(sender.retried!.map((f) => f.name), ['failed.txt']);
    expect(sender.retried!.single.path, '/files/failed.txt');
    expect(sender.retried!.single.lastModified, '2025-01-01T00:00:00Z');
    expect(ref.read(sendProvider), isEmpty);
  });

  test('Should cancel the remote session when the prepare-upload response arrives after a local cancel', () async {
    final client = _HttpClient();
    final ref = RefenaContainer(
      overrides: [
        persistenceProvider.overrideWithValue(MockPersistenceService()),
        settingsProvider.overrideWithNotifier((ref) => _TestSettingsService(MockPersistenceService())),
        httpProvider.overrideWithBuilder((_) => _HttpClientCollection(client)),
        deviceFullInfoProvider.overrideWithBuilder((_) => _createDevice(fingerprint: 'self')),
        parentIsolateProvider.overrideWithReducer(
          notifier: (_) => IsolateController(initialState: ParentIsolateState.initial(_SyncState())),
          reducer: {
            IsolateDiscoveryReportOutboundAction: null,
          },
        ),
      ],
    );

    final session = ref
        .notifier(sendProvider)
        .startSession(
          target: _createDevice(fingerprint: 'target'),
          files: [
            const CrossFile(
              name: 'a.txt',
              fileType: FileType.text,
              size: 1,
              thumbnail: null,
              asset: null,
              path: null,
              bytes: [97],
              lastModified: null,
              lastAccessed: null,
            ),
          ],
          background: true,
        );

    await client.prepareUploadCalled.future;
    final sessionId = ref.read(sendProvider).keys.single;

    ref.notifier(sendProvider).cancelSession(sessionId);
    // The receiver had already answered.
    client.prepareUploadResponse.complete(
      const PrepareUploadResult(
        statusCode: 200,
        response: PrepareUploadResponseDto(sessionId: 'remote-session', files: {'file-id': 'token'}),
      ),
    );
    await session;

    expect(ref.read(sendProvider), isEmpty);
    expect(ref.read(fileTransferProvider).getData(), isEmpty);
    expect(client.canceledSessions, ['remote-session']);
  });

  test('keeps cleared clipboard files until a canceled send actually stops', () async {
    debugHarmonyOSOverride = true;
    final root = Directory.systemTemp.createTempSync('clipboard-send-test-');
    final copy = Directory('${root.path}/localsend-clipboard-file-copy')..createSync();
    final file = File('${copy.path}/item.txt')..writeAsStringSync('a');
    HarmonyClipboardCache.register(copy.path);
    HarmonyTransferRecovery.directory = Directory('${root.path}/recovery');
    addTearDown(() {
      debugHarmonyOSOverride = null;
      HarmonyTransferRecovery.directory = null;
      root.deleteSync(recursive: true);
    });
    final client = _HttpClient();
    final ref = RefenaContainer(
      overrides: [
        globalReduxProvider.overrideWithGlobalReducer(reducer: {ClearCacheAction: null}),
        persistenceProvider.overrideWithValue(MockPersistenceService()),
        settingsProvider.overrideWithNotifier((_) => _TestSettingsService(MockPersistenceService())),
        httpProvider.overrideWithBuilder((_) => _HttpClientCollection(client)),
        deviceFullInfoProvider.overrideWithBuilder((_) => _createDevice(fingerprint: 'self')),
        parentIsolateProvider.overrideWithReducer(
          notifier: (_) => IsolateController(initialState: ParentIsolateState.initial(_SyncState())),
          reducer: {IsolateDiscoveryReportOutboundAction: null},
        ),
      ],
    );
    final selected = CrossFile(
      name: 'item.txt',
      fileType: FileType.text,
      size: 1,
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
    await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddFilesAction(files: [selected], converter: (file) async => file));
    final sending = ref
        .notifier(sendProvider)
        .startSession(
          target: _createDevice(fingerprint: 'target'),
          files: [selected],
          background: true,
        );
    await client.prepareUploadCalled.future;
    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(file.existsSync(), isTrue);
    ref.notifier(sendProvider).cancelSession(ref.read(sendProvider).keys.single);
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(file.existsSync(), isTrue);
    client.prepareUploadResponse.complete(
      const PrepareUploadResult(
        statusCode: 200,
        response: PrepareUploadResponseDto(sessionId: 'remote', files: {}),
      ),
    );
    await sending;
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(copy.existsSync(), isFalse);
  });

  test('cleans clipboard copy after a successful single send closes', () async {
    debugHarmonyOSOverride = true;
    final root = Directory.systemTemp.createTempSync('clipboard-finished-test-');
    final copy = Directory('${root.path}/localsend-clipboard-file-copy')..createSync();
    final file = File('${copy.path}/item.txt')..writeAsStringSync('a');
    HarmonyClipboardCache.register(copy.path);
    HarmonyTransferRecovery.directory = Directory('${root.path}/recovery');
    addTearDown(() {
      debugHarmonyOSOverride = null;
      HarmonyTransferRecovery.directory = null;
      root.deleteSync(recursive: true);
    });
    final crossFile = CrossFile(
      name: 'item.txt',
      fileType: FileType.text,
      size: 1,
      thumbnail: null,
      asset: null,
      path: file.path,
      bytes: null,
      lastModified: null,
      lastAccessed: null,
    );
    final sender = _RetrySender(
      SendSessionState(
        sessionId: 'finished',
        remoteSessionId: 'remote',
        background: false,
        status: SessionStatus.finished,
        target: _createDevice(fingerprint: 'target'),
        files: {
          'file': SendingFile(
            file: const FileDto(id: 'file', fileName: 'item.txt', size: 1, fileType: FileType.text, hash: null, preview: null, metadata: null),
            token: 'token',
            thumbnail: null,
            asset: null,
            path: file.path,
            bytes: null,
            errorMessage: null,
          ),
        },
        hashedFileCount: 1,
        startTime: null,
        endTime: null,
        sendingTasks: [],
        errorMessage: null,
      ),
    );
    final ref = RefenaContainer(
      overrides: [
        globalReduxProvider.overrideWithGlobalReducer(reducer: {ClearCacheAction: null}),
        sendProvider.overrideWithNotifier((_) => sender),
        settingsProvider.overrideWithNotifier((_) => _TestSettingsService(MockPersistenceService())),
      ],
    );
    await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddFilesAction(files: [crossFile], converter: (file) async => file));
    sender.closeSession('finished');
    await ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    expect(ref.read(selectedSendingFilesProvider), isEmpty);
    expect(copy.existsSync(), isFalse);
  });
}

Device _createDevice({required String fingerprint}) {
  return Device(
    signalingId: null,
    ip: '192.168.1.2',
    version: '2.1',
    port: 53317,
    https: true,
    fingerprint: fingerprint,
    alias: 'Nice Banana',
    deviceModel: 'Pixel',
    deviceType: DeviceType.mobile,
    download: false,
    channels: [HttpChannel(host: '192.168.1.2', port: 53317, https: true)],
  );
}
