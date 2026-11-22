import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/pages/progress_page.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

class _Settings extends Fake implements SettingsState {
  @override
  bool get autoFinish => false;
}

class _SettingsService extends SettingsService {
  _SettingsService() : super(MockPersistenceService());
  @override
  SettingsState init() => _Settings();
}

class _Server extends ServerService {
  final ServerState? initial;
  _Server(this.initial);
  @override
  ServerState? init() => initial;
}

class _Send extends SendNotifier {
  final Map<String, SendSessionState> initial;
  _Send(this.initial);
  @override
  Map<String, SendSessionState> init() => initial;
}

void main() {
  for (final (size, receiving, scale, status, showAppBar) in [
    (const Size(360, 720), true, 1.0, SessionStatus.sending, true),
    (const Size(1024, 700), false, 1.0, SessionStatus.sending, false),
    (const Size(1024, 700), false, 1.0, SessionStatus.finishedWithErrors, false),
    (const Size(280, 500), true, 2.0, SessionStatus.finished, false),
    (const Size(600, 300), false, 2.0, SessionStatus.finished, true),
  ]) {
    testWidgets('Harmony progress $size receiving=$receiving scale=$scale status=$status appBar=$showAppBar', (tester) async {
      debugHarmonyOSOverride = true;
      addTearDown(() => debugHarmonyOSOverride = null);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const device = Device(
        signalingId: null,
        ip: '192.168.1.2',
        version: '2.1',
        port: 53317,
        https: true,
        fingerprint: 'id',
        alias: 'Device',
        deviceModel: 'PC',
        deviceType: DeviceType.desktop,
        download: false,
        channels: [],
      );
      const file = FileDto(
        id: 'file',
        fileName: 'a-very-long-filename-包含中文-and-many-words-for-testing.txt',
        size: 123456789,
        fileType: FileType.other,
        hash: null,
        preview: null,
        metadata: null,
      );
      final state = ReceiveSessionState(
        sessionId: 'session',
        status: status,
        sender: device,
        senderAlias: 'Device',
        files: {
          'file': ReceivingFile(
            file: file,
            token: null,
            desiredName: file.fileName,
            path: '/private/received-file.txt',
            savedToGallery: false,
            errorMessage: null,
          ),
        },
        startTime: null,
        endTime: null,
        destinationDirectory: '/private/long/destination/path',
        cacheDirectory: '/private',
        saveToGallery: false,
        createdDirectories: {},
      );
      final server = receiving ? ServerState(alias: 'self', port: 53317, https: true, session: state, web: null) : null;
      final sending = SendSessionState(
        sessionId: 'session',
        remoteSessionId: null,
        background: false,
        status: status,
        target: device,
        files: {'file': SendingFile(file: file, token: null, thumbnail: null, asset: null, path: null, bytes: null, errorMessage: null)},
        hashedFileCount: 1,
        startTime: null,
        endTime: null,
        sendingTasks: null,
        errorMessage: null,
      );
      final transfer = FileTransferNotifier()
        ..setStatus(
          sessionId: 'session',
          fileId: 'file',
          status: switch (status) {
            SessionStatus.finished => FileStatus.finished,
            SessionStatus.finishedWithErrors => FileStatus.failed,
            _ => FileStatus.sending,
          },
        )
        ..setProgress(sessionId: 'session', fileId: 'file', progress: status == SessionStatus.finished ? 1 : 0.4);
      await tester.pumpWidget(
        RefenaScope(
          overrides: [
            settingsProvider.overrideWithNotifier((_) => _SettingsService()),
            serverProvider.overrideWithNotifier((_) => _Server(server)),
            sendProvider.overrideWithNotifier((_) => _Send(receiving ? {} : {'session': sending})),
            fileTransferProvider.overrideWithNotifier((_) => transfer),
          ],
          child: MaterialApp(
            theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                child: ProgressPage(showAppBar: showAppBar, closeSessionOnClose: false, sessionId: 'session'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text(file.fileName),
        80,
        scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
      );
      expect(find.text(file.fileName), findsOneWidget);
      if (!receiving && status == SessionStatus.finishedWithErrors) {
        expect(find.text('Resend failed files'), findsOneWidget);
      }
      await tester.ensureVisible(find.byIcon(Icons.info));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.info));
      await tester.pumpAndSettle();
      expect(find.text(t.general.hide), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (receiving && status == SessionStatus.finished) {
        expect(find.byIcon(Icons.save_alt), findsOneWidget);
        expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }
}
