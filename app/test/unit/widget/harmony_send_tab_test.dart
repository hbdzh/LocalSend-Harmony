import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab_vm.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/logging/discovery_logs_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

class _Isolate extends Fake implements IsolateController {}

class _Favorites extends Fake implements FavoritesService {}

class _Logs extends Fake implements DiscoveryLogger {}

class _Nearby extends NearbyDevicesService {
  _Nearby() : super(isolateController: _Isolate(), favoriteService: _Favorites(), discoveryLogs: _Logs());
  @override
  NearbyDevicesState init() => const NearbyDevicesState(runningFavoriteScan: false, runningIps: {}, devices: {}, signalingDevices: {});
}

void main() {
  for (final size in [const Size(280, 500), const Size(360, 720), const Size(600, 300), const Size(1024, 700)]) {
    for (final selected in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('Harmony send page fits $size with selected=$selected and scale=$scale', (tester) async {
          debugHarmonyOSOverride = true;
          addTearDown(() => debugHarmonyOSOverride = null);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final vm = SendTabVm(
            sendMode: SendMode.single,
            selectedFiles: selected
                ? [
                    const CrossFile(
                      name: 'message.txt',
                      fileType: FileType.text,
                      size: 5,
                      thumbnail: null,
                      asset: null,
                      path: null,
                      bytes: [104, 101, 108, 108, 111],
                      lastModified: null,
                      lastAccessed: null,
                    ),
                  ]
                : [],
            localIps: [],
            nearbyDevices: [],
            favoriteDevices: [],
            onTapAddress: (_) async {},
            onTapFavorite: (_) async {},
            onTapSendMode: (_, _) async {},
            onTapDevice: (_, _) async {},
            onTapDeviceMultiSend: (_, _) async {},
          );
          await tester.pumpWidget(
            RefenaScope(
              overrides: [
                globalReduxProvider.overrideWithGlobalReducer(reducer: {SendTabInitAction: null}),
                sendTabVmProvider.overrideWithBuilder((_) => vm),
                nearbyDevicesProvider.overrideWithNotifier((_) => _Nearby()),
                animationProvider.overrideWithBuilder((_) => false),
              ],
              child: MaterialApp(
                theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
                home: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                    child: const Scaffold(body: SendTab()),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Nearby devices'), findsOneWidget);
          if (selected) expect(find.text('System share'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(milliseconds: 50));
        });
      }
    }
  }
}
