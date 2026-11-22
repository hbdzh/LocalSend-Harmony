import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/receive_history_page.dart';
import 'package:localsend_app/pages/web_share_page.dart';
import 'package:localsend_app/provider/animation_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/ip_helper.dart';
import 'package:localsend_app/util/native/harmony_share.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/animations/initial_fade_transition.dart';
import 'package:localsend_app/widget/column_list_view.dart';
import 'package:localsend_app/widget/custom_icon_button.dart';
import 'package:localsend_app/widget/local_send_logo.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:localsend_app/widget/rotating_widget.dart';
import 'package:localsend_isolates/util/sleep.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

class ReceiveTab extends StatefulWidget {
  const ReceiveTab();

  @override
  State<ReceiveTab> createState() => _ReceiveTabState();
}

class _ReceiveTabState extends State<ReceiveTab> {
  /// Whether the advanced network info is shown
  bool _showAdvanced = false;

  /// Whether the history button is shown
  /// This extra boolean is needed to delay the animation
  bool _showHistoryButton = true;

  Future<void> _toggleAdvanced() async {
    if (_showAdvanced) {
      setState(() => _showAdvanced = false);
      await sleepAsync(200);
      if (mounted) {
        setState(() => _showHistoryButton = true);
      }
    } else {
      setState(() {
        _showAdvanced = true;
        _showHistoryButton = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final alias = context.watch(settingsProvider.select((s) => s.alias));
    final serverState = context.watch(serverProvider);
    final localIps = context.watch(localIpProvider.select((s) => s.localIps));

    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isHarmonyOS ? 720 : ResponsiveListView.defaultMaxWidth),
            child: Padding(
              padding: isHarmonyOS ? const EdgeInsets.fromLTRB(16, 68, 16, 16) : const EdgeInsets.all(30),
              child: ColumnListView(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      constraints: isHarmonyOS ? const BoxConstraints(minHeight: 260) : null,
                      decoration: isHarmonyOS
                          ? BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.11),
                                  Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
                                ],
                              ),
                            )
                          : null,
                      padding: isHarmonyOS ? const EdgeInsets.symmetric(horizontal: 20, vertical: 12) : EdgeInsets.zero,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          InitialFadeTransition(
                            duration: const Duration(milliseconds: 300),
                            delay: const Duration(milliseconds: 200),
                            child: Consumer(
                              builder: (context, ref) {
                                final animations = ref.watch(animationProvider);
                                final activeTab = ref.watch(homePageControllerProvider.select((state) => state.currentTab));
                                return RotatingWidget(
                                  duration: const Duration(seconds: 15),
                                  spinning: serverState != null && animations && activeTab == HomeTab.receive,
                                  child: LocalSendLogo(withText: false, size: isHarmonyOS ? 128 : 200),
                                );
                              },
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              serverState?.alias ?? alias,
                              style: TextStyle(fontSize: isHarmonyOS ? 32 : 48, fontWeight: isHarmonyOS ? FontWeight.w600 : FontWeight.normal),
                            ),
                          ),
                          InitialFadeTransition(
                            duration: const Duration(milliseconds: 300),
                            delay: const Duration(milliseconds: 500),
                            child: Text(
                              serverState == null ? t.general.offline : localIps.map((ip) => '#${ip.visualId}').toSet().join(' '),
                              style: TextStyle(
                                fontSize: isHarmonyOS ? 16 : 24,
                                color: isHarmonyOS ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isHarmonyOS)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () async => context.global.dispatchAsync(NavigateAction.push(const WebSharePage())),
                            icon: const Icon(Icons.language),
                            label: Text(t.receiveTab.link),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => HarmonyShare.openReceivedKnockFiles(context),
                            icon: const Icon(Icons.folder_open),
                            label: Text(Localizations.localeOf(context).languageCode == 'zh' ? '碰一碰接收文件' : 'Tap received files'),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Center(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await context.global.dispatchAsync(NavigateAction.push(const WebSharePage()));
                          },
                          icon: Icon(Icons.language),
                          label: Text(t.receiveTab.link),
                        ),
                      ),
                    ),
                    if (isHarmonyOS)
                      Center(
                        child: TextButton.icon(
                          onPressed: () => HarmonyShare.openReceivedKnockFiles(context),
                          icon: const Icon(Icons.folder_open),
                          label: Text(Localizations.localeOf(context).languageCode == 'zh' ? '碰一碰接收文件' : 'Tap received files'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 15),
                ],
              ),
            ),
          ),
        ),
        if (isHarmonyOS)
          Positioned(
            top: 22,
            left: 24,
            right: 120,
            child: Text(
              t.receiveTab.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        _InfoBox(
          serverState: serverState,
          localIps: localIps,
          showAdvanced: _showAdvanced,
        ),
        _CornerButtons(
          showAdvanced: _showAdvanced,
          showHistoryButton: _showHistoryButton,
          toggleAdvanced: _toggleAdvanced,
        ),
      ],
    );
  }
}

class _CornerButtons extends StatelessWidget {
  final bool showAdvanced;
  final bool showHistoryButton;
  final Future<void> Function() toggleAdvanced;

  const _CornerButtons({
    required this.showAdvanced,
    required this.showHistoryButton,
    required this.toggleAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (!showAdvanced)
              AnimatedOpacity(
                opacity: showHistoryButton ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: CustomIconButton(
                  onPressed: () async {
                    await context.push(() => const ReceiveHistoryPage());
                  },
                  child: const Icon(Icons.history),
                ),
              ),
            CustomIconButton(
              key: const ValueKey('info-btn'),
              onPressed: toggleAdvanced,
              child: const Icon(Icons.info),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final ServerState? serverState;
  final List<String> localIps;
  final bool showAdvanced;

  const _InfoBox({
    required this.serverState,
    required this.localIps,
    required this.showAdvanced,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      crossFadeState: showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
      duration: const Duration(milliseconds: 200),
      firstChild: Container(),
      secondChild: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: isHarmonyOS ? const EdgeInsets.fromLTRB(15, 64, 15, 15) : const EdgeInsets.all(15),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isHarmonyOS ? 440 : double.infinity),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Table(
                  columnWidths: {
                    0: const IntrinsicColumnWidth(),
                    1: const IntrinsicColumnWidth(),
                    2: isHarmonyOS ? const FlexColumnWidth() : const IntrinsicColumnWidth(),
                  },
                  children: [
                    TableRow(
                      children: [
                        Text(t.receiveTab.infoBox.alias),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 30),
                          child: SelectableText(serverState?.alias ?? '-'),
                        ),
                      ],
                    ),
                    TableRow(
                      children: [
                        Text(t.receiveTab.infoBox.ip),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (localIps.isEmpty) Text(t.general.unknown),
                            ...localIps.map((ip) => SelectableText(ip)),
                          ],
                        ),
                      ],
                    ),
                    TableRow(
                      children: [
                        Text(t.receiveTab.infoBox.port),
                        const SizedBox(width: 10),
                        SelectableText(serverState?.port.toString() ?? '-'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
