import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_isolates/util/transfer_notification.dart';

class HarmonyWindow {
  static const channel = MethodChannel('org.localsend.localsend_app/harmony_window');
  static bool _dialogOpen = false;
  static BuildContext? _attachedContext;

  static Future<void> setTopmost(bool enabled) => channel.invokeMethod<void>('setTopmost', {'enabled': enabled});

  static Future<void> setTray(bool enabled) => channel.invokeMethod<void>('setTray', {'enabled': enabled});

  static Future<({bool supported, bool? enabled})> autoStartupStatus() async {
    final value = await channel.invokeMapMethod<String, bool>('autoStartupStatus');
    if (value == null) throw StateError('Missing startup status');
    return (supported: value['supported'] == true, enabled: value['enabled']);
  }

  static void attach(BuildContext context) {
    _attachedContext = context;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'trayMinimizeFailed') {
        if (context.mounted) {
          final chinese = Localizations.localeOf(context).languageCode == 'zh';
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(chinese ? '无法最小化窗口。' : 'Could not minimize the window.')));
        }
        return null;
      }
      if (call.method != 'willClose') return 'close';
      final trayEnabled = (call.arguments as Map?)?['trayEnabled'] == true;
      final active = TransferNotification.hasActiveTransfers;
      if (!active) return trayEnabled ? 'minimize' : 'close';
      if (trayEnabled && TransferNotification.harmonyBackgroundReady) return 'minimize';
      if (!context.mounted || _dialogOpen) return 'cancel';
      _dialogOpen = true;
      try {
        final chinese = Localizations.localeOf(context).languageCode == 'zh';
        return await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: Text(chinese ? '文件正在传输' : 'Transfer in progress'),
                content: Text(
                  TransferNotification.harmonyBackgroundReady
                      ? (chinese ? '关闭应用可能中断传输。可以最小化窗口继续传输。' : 'Closing the app may interrupt the transfer. You can minimize the window.')
                      : (chinese
                            ? '后台传输尚未就绪或不可用，最小化可能中断传输。'
                            : 'Background transfer is not ready or unavailable. Minimizing may interrupt the transfer.'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context, 'cancel'), child: Text(chinese ? '取消' : 'Cancel')),
                  TextButton(onPressed: () => Navigator.pop(context, 'minimize'), child: Text(chinese ? '最小化' : 'Minimize')),
                  TextButton(onPressed: () => Navigator.pop(context, 'close'), child: Text(chinese ? '关闭' : 'Close')),
                ],
              ),
            ) ??
            'cancel';
      } finally {
        _dialogOpen = false;
      }
    });
  }

  static void detach([BuildContext? context]) {
    if (context != null && !identical(_attachedContext, context)) return;
    _attachedContext = null;
    channel.setMethodCallHandler(null);
  }
}
