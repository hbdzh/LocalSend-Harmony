import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/network_state.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/address_input_dialog.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

class _Settings extends Fake implements SettingsState {
  @override
  int get port => 53317;
  @override
  bool get https => true;
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
  NetworkState init() => const NetworkState(localIps: ['192.168.1.20'], initialized: true);
}

void main() {
  for (final size in [const Size(280, 500), const Size(600, 300), const Size(1024, 700)]) {
    testWidgets('Harmony address dialog wraps and switches mode at $size', (tester) async {
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
          ],
          child: MaterialApp(
            theme: harmonyTheme(ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue))),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
                child: Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<void>(context: context, builder: (_) => const AddressInputDialog()),
                    child: const Text('Address'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Address'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ChoiceChip), findsNWidgets(2));
      await tester.ensureVisible(find.text(t.dialogs.addressInput.ip).first);
      await tester.tap(find.text(t.dialogs.addressInput.ip).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('input-_InputMode.ip')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
