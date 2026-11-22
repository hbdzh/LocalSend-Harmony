import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/harmony_clipboard_cache.dart';
import 'package:localsend_app/util/native/harmony_drop.dart';
import 'package:localsend_app/util/native/harmony_empty_folder.dart';
import 'package:localsend_app/util/native/harmony_recovery_ui.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:localsend_app/util/native/harmony_window.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum HomeTab {
  receive(Icons.wifi),
  send(Icons.send),
  settings(Icons.settings)
  ;

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.receive:
        return t.receiveTab.title;
      case HomeTab.send:
        return t.sendTab.title;
      case HomeTab.settings:
        return t.settingsTab.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;
  bool _preparingDrop = false;
  int? _dropListener;

  @override
  void initState() {
    super.initState();

    if (isHarmonyOS) {
      HarmonyWindow.attach(context);
      _dropListener = HarmonyDrop.listen(
        onEntered: () {
          if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
            setState(() => _dragAndDropIndicator = true);
          }
        },
        onExited: () {
          if (mounted) setState(() => _dragAndDropIndicator = false);
        },
        onDropped: (paths, directories, failed) async {
          if (!mounted) return false;
          setState(() {
            _dragAndDropIndicator = false;
            _preparingDrop = directories.isNotEmpty;
          });
          if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
            setState(() => _preparingDrop = false);
            return false;
          }
          var accepted = false;
          var zipped = 0;
          if (paths.isNotEmpty) {
            try {
              await ref
                  .redux(selectedSendingFilesProvider)
                  .dispatchAsync(
                    AddFilesAction(files: paths.map(File.new).toList(), converter: CrossFileConverters.convertFile),
                  );
              accepted = true;
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.general.error)));
              }
              failed += paths.length;
            }
          }
          for (final directory in directories) {
            File? zip;
            try {
              zip = await prepareHarmonyFolder(directory);
              if (zip != null) {
                await ref
                    .redux(selectedSendingFilesProvider)
                    .dispatchAsync(
                      AddFilesAction(files: [zip], converter: CrossFileConverters.convertFile),
                    );
                zipped++;
              } else {
                await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory, followLinks: false));
              }
              accepted = true;
            } catch (_) {
              if (zip != null) {
                try {
                  await zip.parent.delete(recursive: true);
                } catch (_) {}
              }
              failed++;
            }
          }
          if (accepted && mounted) {
            context.read(homePageControllerProvider).changeTab(HomeTab.send);
          }
          if (mounted) {
            setState(() => _preparingDrop = false);
            if (zipped > 0 || failed > 0) {
              final chinese = Localizations.localeOf(context).languageCode == 'zh';
              final zipMessage = chinese
                  ? '包含空文件夹，已打包为 ZIP；接收后解压即可恢复。'
                  : 'Folders with empty directories were packed as ZIP files. Extract them after receiving.';
              final errorMessage = '$failed ${t.general.files}: ${t.general.error}';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text([if (zipped > 0) zipMessage, if (failed > 0) errorMessage].join('\n'))),
              );
            }
          }
          return accepted;
        },
      );
    }

    ensureRef((ref) async {
      var pendingSends = <HarmonyRecoveryItem>[];
      var pendingReceives = <(File, String)>[];
      var recoveryReadFailed = false;
      if (isHarmonyOS && widget.appStart) {
        try {
          pendingSends = HarmonyTransferRecovery.readPending();
          pendingReceives = await HarmonyRecoveryUi.receiveRecords(includeActive: true);
          HarmonyRecoveryUi.interruptedAtStartup = pendingReceives;
        } catch (error) {
          recoveryReadFailed = true;
          debugPrint('Could not read receive recovery records: $error');
        }
      }
      if (!mounted) return;
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(widget.initialTab));
      await postInit(context, ref, widget.appStart);
      if (isHarmonyOS && widget.appStart && mounted) {
        unawaited(ref.global.dispatchAsync(CleanHarmonyClipboardCacheAction()));
        unawaited(ref.global.dispatchAsync(CleanLegacyHarmonyClipboardCacheAction()));
        if (recoveryReadFailed) {
          final chinese = Localizations.localeOf(context).languageCode == 'zh';
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(chinese ? '无法读取传输恢复记录，请稍后在传输恢复中检查。' : 'Could not read transfer recovery records. Check transfer recovery later.'),
            ),
          );
        }
        await HarmonyRecoveryUi.showSend(context, pendingSends);
        if (mounted) await HarmonyRecoveryUi.showReceive(context, pendingReceives);
      }
      if (isHarmonyOS && widget.appStart && ref.read(settingsProvider).minimizeToTray && mounted) {
        try {
          await HarmonyWindow.setTray(true);
        } catch (_) {
          await ref.notifier(settingsProvider).setMinimizeToTray(false);
          if (mounted) {
            final chinese = Localizations.localeOf(context).languageCode == 'zh';
            ScaffoldMessenger.maybeOf(
              context,
            )?.showSnackBar(SnackBar(content: Text(chinese ? '状态栏图标不可用，已关闭最小化设置。' : 'Status bar icon unavailable; minimize on close was disabled.')));
          }
        }
      }
      if (isHarmonyOS && widget.appStart && ref.read(settingsProvider).alwaysOnTop && mounted) {
        try {
          await HarmonyWindow.setTopmost(true);
        } catch (_) {
          if (mounted) {
            final chinese = Localizations.localeOf(context).languageCode == 'zh';
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(chinese ? '无法恢复窗口置顶，请检查窗口模式和系统权限。' : 'Could not restore window pinning. Check window mode and permission.')),
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    if (isHarmonyOS) HarmonyWindow.detach(context);
    if (_dropListener != null) HarmonyDrop.dispose(_dropListener!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);

    final content = ResponsiveBuilder(
      builder: (sizingInformation) {
        return Scaffold(
          body: Row(
            children: [
              if (!sizingInformation.useBottomNavigation)
                NavigationRail(
                  selectedIndex: vm.currentTab.index,
                  onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                  extended: sizingInformation.isDesktop,
                  backgroundColor: isHarmonyOS ? Theme.of(context).navigationRailTheme.backgroundColor : Theme.of(context).cardColorWithElevation,
                  leading: sizingInformation.isDesktop
                      ? const Column(
                          children: [
                            SizedBox(height: 20),
                            Text(
                              'LocalSend',
                              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 20),
                          ],
                        )
                      : null,
                  destinations: HomeTab.values.map((tab) {
                    return NavigationRailDestination(
                      icon: Icon(tab.icon),
                      label: Text(tab.label),
                    );
                  }).toList(),
                ),
              Expanded(
                child: SafeArea(
                  left: sizingInformation.useBottomNavigation,
                  child: Stack(
                    children: [
                      PageView(
                        controller: vm.controller,
                        physics: const NeverScrollableScrollPhysics(),
                        children: const [
                          ReceiveTab(),
                          SendTab(),
                          SettingsTab(),
                        ],
                      ),
                      if (_dragAndDropIndicator || _preparingDrop)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.file_download, size: 128),
                              const SizedBox(height: 30),
                              Text(
                                _preparingDrop
                                    ? (Localizations.localeOf(context).languageCode == 'zh' ? '正在准备文件…' : 'Preparing files…')
                                    : t.sendTab.placeItems,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: sizingInformation.useBottomNavigation
              ? NavigationBar(
                  selectedIndex: vm.currentTab.index,
                  onDestinationSelected: (index) => vm.changeTab(HomeTab.values[index]),
                  destinations: HomeTab.values.map((tab) {
                    return NavigationDestination(icon: Icon(tab.icon), label: tab.label);
                  }).toList(),
                )
              : null,
        );
      },
    );

    if (isHarmonyOS) {
      return content;
    }

    return DropTarget(
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        // the drop may contain a mix of files and directories
        final droppedDirectories = event.files.where((file) => Directory(file.path).existsSync()).toList();
        final droppedFiles = event.files.where((file) => !Directory(file.path).existsSync()).toList();

        for (final directory in droppedDirectories) {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory.path));
        }

        if (droppedFiles.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: droppedFiles,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        vm.changeTab(HomeTab.send);
      },
      child: content,
    );
  }
}
