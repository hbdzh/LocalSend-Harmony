import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/receive_history_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/util/native/harmony_export.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

final _logger = Logger('HarmonyShare');

class HarmonyShare {
  static const channel = MethodChannel('org.localsend.localsend_app/harmony_share');

  static Future<void> shareFile(BuildContext context, String path) async {
    try {
      await channel.invokeMethod<void>('shareFile', {'path': path});
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.general.error)));
      }
      _logger.warning('Could not open HarmonyOS share panel', error);
    }
  }

  static Future<void> shareSelection(BuildContext context, List<CrossFile> files, {required bool knock}) async {
    try {
      final paths = <String>[];
      final texts = <String>[];
      for (final file in files) {
        if (file.path != null) {
          paths.add(file.path!);
        } else if (file.fileType == FileType.text && file.bytes != null) {
          texts.add(utf8.decode(file.bytes!));
        } else {
          throw StateError('This selection includes content that cannot be shared through HarmonyOS');
        }
      }
      await channel.invokeMethod<void>(knock ? 'armKnock' : 'shareSelection', {'paths': paths, 'texts': texts});
      if (knock && context.mounted) {
        final chinese = Localizations.localeOf(context).languageCode == 'zh';
        try {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(chinese ? '碰一碰分享' : 'Tap to share'),
              content: Text(
                chinese
                    ? '请保持此界面打开，将已解锁的设备轻碰。离开应用后需要重新打开此界面。系统会显示分享确认卡片。'
                    : 'Keep this screen open and tap the unlocked devices together. Reopen this screen after leaving the app. The system will show a confirmation card.',
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(t.general.close))],
            ),
          );
        } finally {
          await channel.invokeMethod<void>('disarmKnock');
        }
      } else if (knock) {
        await channel.invokeMethod<void>('disarmKnock');
      }
    } catch (error, stack) {
      _logger.warning('Could not share selected content', error, stack);
      if (context.mounted) {
        final chinese = Localizations.localeOf(context).languageCode == 'zh';
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(chinese ? '无法分享所选内容，请检查文件或设备支持情况。' : 'Could not share this selection. Check the files and device support.')),
        );
      }
    }
  }

  /// Files are kept in application storage independently of the history preference.
  static Future<({List<String> paths, int failed})> _listKnockFiles(String method) async {
    final result = await channel.invokeMapMethod<String, dynamic>(method);
    if (result == null) throw StateError('Missing tap file list');
    final paths = (result['paths'] as List).cast<String>()..sort();
    return (paths: paths, failed: result['failed'] as int);
  }

  static Future<List<String>> listReceivedKnockFiles() async => (await _listKnockFiles('listKnockFiles')).paths;

  static Future<void> openReceivedKnockFiles(BuildContext context) async {
    try {
      final received = await _listKnockFiles('listKnockFiles');
      final pending = await _listKnockFiles('listPendingKnockFiles');
      if (context.mounted) {
        await _showKnockFiles(context, received.paths, 0, pending: pending.paths, readFailures: received.failed + pending.failed);
      }
    } catch (error, stack) {
      _logger.warning('Could not list tap received files', error, stack);
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(t.general.error)));
      }
    }
  }

  static Future<void> _showKnockFiles(
    BuildContext context,
    List<String> paths,
    int failed, {
    List<String> pending = const [],
    int readFailures = 0,
  }) async {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final recoverable = [...pending];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(chinese ? '碰一碰接收文件' : 'Tap received files'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (failed > 0) Text(chinese ? '$failed 个文件接收失败' : '$failed files could not be received'),
                  if (readFailures > 0) Text(chinese ? '$readFailures 项文件或目录无法读取' : '$readFailures files or folders could not be read'),
                  if (paths.isEmpty && recoverable.isEmpty && failed == 0 && readFailures == 0) Text(chinese ? '暂无接收文件' : 'No received files'),
                  for (final path in paths)
                    ListTile(
                      title: Text(p.basename(path)),
                      trailing: IconButton(
                        icon: const Icon(Icons.save_alt),
                        tooltip: t.general.save,
                        onPressed: () => saveReceivedFile(dialogContext, path),
                      ),
                    ),
                  if (recoverable.isNotEmpty) ...[
                    const Divider(),
                    Text(chinese ? '接收中断的文件可能不完整，请自行检查后使用。' : 'Interrupted files may be incomplete. Check them before use.'),
                    for (final path in recoverable)
                      ListTile(
                        title: Text(p.basename(path)),
                        subtitle: Text(chinese ? '可能不完整' : 'Possibly incomplete'),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.save_alt),
                              tooltip: t.general.save,
                              onPressed: () => saveReceivedFile(dialogContext, path),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: chinese ? '删除残留文件' : 'Delete incomplete file',
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: dialogContext,
                                  builder: (confirmContext) => AlertDialog(
                                    title: Text(chinese ? '删除残留文件？' : 'Delete incomplete file?'),
                                    content: Text(p.basename(path)),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(confirmContext, false), child: Text(t.general.cancel)),
                                      TextButton(onPressed: () => Navigator.pop(confirmContext, true), child: Text(chinese ? '删除' : 'Delete')),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !dialogContext.mounted) return;
                                try {
                                  await channel.invokeMethod<void>('deletePendingKnockFile', {'path': path});
                                  if (dialogContext.mounted) setDialogState(() => recoverable.remove(path));
                                } catch (error, stack) {
                                  _logger.warning('Could not delete incomplete tap file', error, stack);
                                  if (dialogContext.mounted) {
                                    ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(SnackBar(content: Text(t.general.error)));
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t.general.close))],
        ),
      ),
    );
  }

  static Future<bool> _handleKnock(Ref ref, List<String> paths, int failed) async {
    final available = <String>[];
    for (final path in paths) {
      try {
        final file = File(path);
        final size = await file.length();
        available.add(path);
        if (ref.read(receiveHistoryProvider).any((entry) => entry.id == path)) continue;
        await ref
            .redux(receiveHistoryProvider)
            .dispatchAsync(
              AddHistoryEntryAction(
                entryId: path,
                fileName: p.basename(path),
                fileType: FileType.other,
                path: path,
                savedToGallery: false,
                isMessage: false,
                fileSize: size,
                senderAlias: 'Huawei Share',
                timestamp: DateTime.now().toUtc(),
              ),
            );
      } catch (error, stack) {
        // One missing file or a history error must not discard the rest of the batch.
        _logger.warning('Could not record a received tap file', error, stack);
        if (!available.contains(path)) failed++;
      }
    }
    try {
      final context = Routerino.context;
      if (context.mounted) await _showKnockFiles(context, available, failed);
    } catch (error, stack) {
      // Files can still be reopened through the receive tab after the UI starts.
      _logger.warning('Could not show tap receive result', error, stack);
    }
    return true;
  }

  static Future<void> start(Ref ref) async {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'received') return null;
      final data = Map<Object?, Object?>.from(call.arguments as Map);
      final paths = (data['paths'] as List).cast<String>();
      final texts = (data['texts'] as List).cast<String>();
      final failed = data['failed'] as int;
      if (data['kind'] == 'knock') return _handleKnock(ref, paths, failed);
      if (failed > 0) {
        _logger.warning('Could not import $failed shared items');
        try {
          final context = Routerino.context;
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('$failed ${t.general.files}: ${t.general.error}')));
          }
        } catch (_) {
          // The first frame may not have mounted yet; importing still proceeds.
        }
      }
      try {
        if (paths.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(files: paths.map(File.new).toList(), converter: CrossFileConverters.convertFile),
              );
        }
        for (final text in texts) {
          ref.redux(selectedSendingFilesProvider).dispatch(AddMessageAction(message: text));
        }
      } catch (error, stack) {
        _logger.warning('Could not import shared content', error, stack);
        return false;
      }
      try {
        if ((paths.isNotEmpty || texts.isNotEmpty) && ref.read(homePageControllerProvider).controller.hasClients) {
          ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));
        }
      } catch (error, stack) {
        // Import already succeeded: never retry it merely because the page moved.
        _logger.warning('Could not navigate to shared content', error, stack);
      }
      return true;
    });
    await channel.invokeMethod<void>('ready');
  }
}
