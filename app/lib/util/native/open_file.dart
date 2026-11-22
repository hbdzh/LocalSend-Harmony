import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/util/native/channel/android_channel.dart' as android_channel;
import 'package:localsend_app/util/native/harmony_export.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:localsend_app/widget/dialogs/cannot_open_file_dialog.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';

/// Opens the selected file which is stored on the device.
Future<void> openFile(
  BuildContext context,
  FileType fileType,
  String filePath, {
  void Function()? onDeleteTap,
}) async {
  if (isHarmonyOS) {
    try {
      await const MethodChannel('org.localsend.localsend_app/harmony_device').invokeMethod<void>('openFile', {'path': filePath});
    } catch (_) {
      if (context.mounted) {
        final chinese = Localizations.localeOf(context).languageCode == 'zh';
        final save = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(chinese ? '无法打开文件' : 'Could not open file'),
            content: Text(chinese ? '请检查文件是否存在，或保存后使用其他应用打开。' : 'Check that the file exists, or save it and open it with another app.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(chinese ? '关闭' : 'Close')),
              TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(chinese ? '保存' : 'Save')),
            ],
          ),
        );
        if (save == true && context.mounted) await saveReceivedFile(context, filePath);
      }
    }
    return;
  }
  if ((fileType == FileType.apk || filePath.toLowerCase().endsWith('.apk')) && checkPlatform([TargetPlatform.android])) {
    await Permission.requestInstallPackages.request();
  }

  if (filePath.startsWith('content://')) {
    await android_channel.openContentUri(uri: filePath);
    return;
  }

  final fileOpenResult = await OpenFile.open(filePath);
  if (fileOpenResult.type != ResultType.done && context.mounted) {
    await CannotOpenFileDialog.open(context, filePath, onDeleteTap);
  }
}
