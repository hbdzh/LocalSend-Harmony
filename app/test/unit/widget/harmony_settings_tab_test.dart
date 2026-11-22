import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab_controller.dart';
import 'package:localsend_app/pages/tabs/settings_tab_vm.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/provider/version_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_isolates/isolate.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/device_info_result.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

class _Isolate extends Fake implements IsolateController {}

class _LocalIp extends Fake implements LocalIpService {}

class _Server extends Fake implements ServerService {}

class _SettingsController extends SettingsTabController {
  _SettingsController({
    required super.settingsService,
    required super.serverNotifier,
    required super.isolateController,
    required super.localIpService,
    required super.initialDeviceInfo,
    required super.supportsDynamicColors,
  });
  @override
  get initialAction => null;
}

void main() {
  for (final size in [const Size(280, 500), const Size(360, 720), const Size(600, 300), const Size(1024, 700)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Harmony settings page fits $size with text scale $scale', (tester) async {
        debugHarmonyOSOverride = true;
        addTearDown(() => debugHarmonyOSOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final persistence = MockPersistenceService();
        when(persistence.getCustomColor()).thenReturn(Colors.blue);
        final settings = SettingsService(persistence);
        const state = SettingsState(
          showToken: 'token',
          alias: 'Harmony device',
          theme: ThemeMode.system,
          colorMode: ColorMode.localsend,
          customColor: Colors.blue,
          locale: null,
          port: 53317,
          networkWhitelist: null,
          networkBlacklist: null,
          multicastGroup: '224.0.0.167',
          destination: null,
          saveToGallery: false,
          saveToHistory: true,
          quickSave: false,
          quickSaveFromFavorites: false,
          receivePin: null,
          autoFinish: false,
          minimizeToTray: false,
          https: true,
          sendMode: SendMode.single,
          saveWindowPlacement: false,
          alwaysOnTop: false,
          enableAnimations: false,
          deviceType: null,
          deviceModel: null,
          shareViaLinkAutoAccept: false,
          receiveViaLinkAutoAccept: false,
          createChecksums: false,
          verifyChecksums: false,
          discoveryTimeout: 5,
          advancedSettings: false,
        );
        final device = DeviceInfoResult(deviceType: DeviceType.mobile, deviceModel: 'HarmonyOS', androidSdkInt: null);
        final controllers = List.generate(5, (_) => TextEditingController());
        final vm = SettingsTabVm(
          advanced: false,
          aliasController: controllers[0],
          deviceModelController: controllers[1],
          portController: controllers[2],
          timeoutController: controllers[3],
          multicastController: controllers[4],
          settings: state,
          serverState: null,
          deviceInfo: device,
          colorModes: ColorMode.values,
          autoStart: false,
          autoStartLaunchHidden: false,
          showInContextMenu: false,
          softwareRendering: false,
          onChangeTheme: (_, _) {},
          onChangeColorMode: (_, _) {},
          onTapLanguage: (_) {},
          onToggleAutoStart: (_) {},
          onToggleAutoStartLaunchHidden: (_) {},
          onToggleShowInContextMenu: (_) {},
          onToggleSoftwareRendering: (_) {},
          onTapRestartServer: (_) {},
          onTapStartServer: (_) {},
          onTapStopServer: () {},
          onTapAdvanced: (_) {},
        );
        await tester.pumpWidget(
          RefenaScope(
            overrides: [
              settingsTabControllerProvider.overrideWithReducer(
                notifier: (_) => _SettingsController(
                  settingsService: settings,
                  serverNotifier: _Server(),
                  isolateController: _Isolate(),
                  localIpService: _LocalIp(),
                  initialDeviceInfo: device,
                  supportsDynamicColors: true,
                ),
                initialState: vm,
                reducer: {},
              ),
              versionProvider.overrideWithFuture((_) async => VersionData(version: '1', buildNumber: '1')),
            ],
            child: MaterialApp(
              theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: const Scaffold(body: SettingsTab()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
