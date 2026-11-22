import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/model/state/network_state.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

class _Settings extends Fake implements SettingsState {
  @override
  String get alias => 'A very long local device name that should fit';
  @override
  bool get enableAnimations => false;
}

class _SettingsService extends SettingsService {
  _SettingsService() : super(MockPersistenceService());
  @override
  SettingsState init() => _Settings();
}

class _LocalIp extends LocalIpService {
  _LocalIp() : super(_SettingsService());
  @override
  get initialAction => null;
  @override
  NetworkState init() => const NetworkState(localIps: ['fe80::1234:5678:9abc:def0%en0'], initialized: true);
}

void main() {
  for (final size in [const Size(280, 500), const Size(360, 720), const Size(600, 300), const Size(1024, 700)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('Harmony receive page and device information fit $size at scale=$scale', (tester) async {
        debugHarmonyOSOverride = true;
        addTearDown(() => debugHarmonyOSOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RefenaScope(
            overrides: [
              settingsProvider.overrideWithNotifier((_) => _SettingsService()),
              localIpProvider.overrideWithNotifier((_) => _LocalIp()),
              animationProvider.overrideWithBuilder((_) => false),
            ],
            child: MaterialApp(
              theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
              home: Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: const Scaffold(body: ReceiveTab()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('info-btn')));
        await tester.pumpAndSettle();
        expect(find.text('fe80::1234:5678:9abc:def0%en0'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 50));
      });
    }
  }
}
