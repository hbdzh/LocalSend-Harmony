import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/directories.dart';
import 'package:localsend_app/util/native/harmony_clipboard_cache.dart';
import 'package:localsend_app/util/native/harmony_export.dart';
import 'package:localsend_app/util/native/harmony_share.dart';
import 'package:localsend_app/util/native/harmony_transfer_recovery.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:localsend_isolates/util/harmony_receive_recovery.dart';
import 'package:path/path.dart' as p;
import 'package:refena_flutter/refena_flutter.dart';

class HarmonyRecoveryUi {
  // Active markers observed before the server starts belong to the previous process.
  static List<(File, String)> interruptedAtStartup = [];

  static Future<List<(File, String)>> receiveRecords({bool includeActive = false}) async {
    final cache = await getCacheDirectory();
    final support = HarmonyTransferRecovery.directory?.parent.path;
    return [
      if (support != null) ...HarmonyReceiveRecovery.pending(support, includeActive: includeActive),
      if (support != cache) ...HarmonyReceiveRecovery.pending(cache, includeActive: includeActive),
    ];
  }

  static Future<void> open(BuildContext context) async {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final selection = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(chinese ? '传输恢复' : 'Transfer recovery'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'send'), child: Text(chinese ? '未完成的发送' : 'Unfinished sends')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'receive'), child: Text(chinese ? '接收文件检查' : 'Check received files')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'knock'), child: Text(chinese ? '碰一碰接收文件' : 'Tap received files')),
        ],
      ),
    );
    if (!context.mounted || selection == null) return;
    try {
      if (selection == 'send') {
        final sessions = context.ref.read(sendProvider);
        final pending = HarmonyTransferRecovery.readPending().where((item) {
          final status = sessions[p.basename(item.record.parent.path)]?.status;
          return status == null || status == SessionStatus.finishedWithErrors;
        }).toList();
        if (context.mounted) await showSend(context, pending, showEmpty: true);
      } else if (selection == 'knock') {
        await HarmonyShare.openReceivedKnockFiles(context);
      } else {
        final paths = <String, (File, String)>{};
        for (final item in [...interruptedAtStartup, ...await receiveRecords()]) {
          if (item.$1.existsSync()) paths[item.$1.path] = item;
        }
        if (context.mounted) await showReceive(context, paths.values.toList(), showEmpty: true);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(chinese ? '无法读取恢复记录。' : 'Could not read recovery records.')));
      }
    }
  }

  static Future<void> showSend(BuildContext context, List<HarmonyRecoveryItem> pending, {bool showEmpty = false}) async {
    if (pending.isEmpty && !showEmpty) return;
    final available = pending.where((item) => item.file != null).toList();
    final unreadable = pending.any((item) => item.sourcePath == null);
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final decision = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(chinese ? '找回未完成的发送' : 'Recover unfinished sends'),
        content: Text(
          pending.isEmpty
              ? (chinese ? '没有待恢复的发送。' : 'No unfinished sends.')
              : (chinese
                        ? '可重新选择 ${available.length} 个文件；${pending.length - available.length} 个文件已变更或不可访问。请重新选择接收设备并从头发送，已完成的文件也可能需要核对。'
                        : '${available.length} files can be selected again; ${pending.length - available.length} changed or are inaccessible. Choose the recipient and resend from the beginning; check files that may already have completed.') +
                    (unreadable
                        ? (chinese
                              ? '\n\n部分恢复记录无法读取，暂存文件清理已暂停。确认不再需要后，可清除记录。'
                              : '\n\nSome recovery records cannot be read, so temporary file cleanup is paused. Clear the records when they are no longer needed.')
                        : ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(chinese ? '关闭' : 'Close')),
          if (pending.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'discard'), child: Text(chinese ? '清除记录' : 'Clear records')),
          if (available.isNotEmpty)
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'restore'), child: Text(chinese ? '恢复文件选择' : 'Restore selection')),
        ],
      ),
    );
    if (!context.mounted || decision == null) return;
    if (decision == 'restore') {
      await context.ref
          .redux(selectedSendingFilesProvider)
          .dispatchAsync(
            AddFilesAction(files: available.map((item) => item.file!), converter: (file) async => file),
          );
      if (!context.mounted) return;
      HarmonyTransferRecovery.markRestored(available);
      context.read(homePageControllerProvider).changeTab(HomeTab.send);
    } else if (decision == 'discard') {
      for (final item in pending) {
        try {
          item.discard();
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(chinese ? '部分记录无法清除。' : 'Some records could not be removed.')));
          }
        }
      }
      if (context.mounted) await context.global.dispatchAsync(CleanHarmonyClipboardCacheAction());
    }
  }

  static Future<void> showReceive(BuildContext context, List<(File, String)> pending, {bool showEmpty = false}) async {
    if (pending.isEmpty && !showEmpty) return;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final clear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(chinese ? '检查中断的接收文件' : 'Check interrupted receives'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pending.isEmpty
                      ? (chinese ? '没有待检查的文件。' : 'No files to check.')
                      : (chinese
                            ? '以下文件可能不完整，也可能已接收完成。请在文件管理器中检查并按需删除；清除记录不会删除文件。'
                            : 'These files may be incomplete or already finished. Check them in the file manager and delete as needed; clearing records does not delete files.'),
                ),
                for (final (_, path) in pending)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(path),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: chinese ? '复制路径' : 'Copy path',
                          icon: const Icon(Icons.copy),
                          onPressed: () => Clipboard.setData(ClipboardData(text: path)),
                        ),
                        IconButton(
                          tooltip: chinese ? '另存以检查' : 'Save a copy to inspect',
                          icon: const Icon(Icons.save_alt),
                          onPressed: () => saveReceivedFile(dialogContext, path),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(chinese ? '关闭' : 'Close')),
          if (pending.isNotEmpty) TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(chinese ? '清除记录' : 'Clear records')),
        ],
      ),
    );
    if (clear == true) {
      for (final (marker, _) in pending) {
        try {
          HarmonyReceiveRecovery.forget(marker);
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(chinese ? '部分记录无法清除。' : 'Some records could not be removed.')));
          }
        }
      }
    }
  }
}
