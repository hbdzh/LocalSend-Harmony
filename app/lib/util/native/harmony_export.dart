import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/dialogs/error_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('org.localsend.localsend_app/harmony_device');
const _preferredFolderKey = 'harmony_export_folder_uri';

Future<String?> getHarmonyExportFolder() async => (await SharedPreferences.getInstance()).getString(_preferredFolderKey);

Future<String?> chooseHarmonyExportFolder() async {
  final folder = await _channel.invokeMethod<String>('chooseExportFolder');
  if (folder != null) await (await SharedPreferences.getInstance()).setString(_preferredFolderKey, folder);
  return folder;
}

Future<void> clearHarmonyExportFolder() async => (await SharedPreferences.getInstance()).remove(_preferredFolderKey);

/// Shows the system save picker and copies a received file to its chosen URI.
/// Returns false when the picker is dismissed without choosing a destination.
Future<bool> exportHarmonyFile(String sourcePath) async {
  final folder = await getHarmonyExportFolder();
  return await _channel.invokeMethod<bool>('exportFile', {
        'path': sourcePath,
        'name': path.basename(sourcePath),
        'preferredFolder': ?folder,
      }) ??
      false;
}

Future<void> saveReceivedFile(BuildContext context, String sourcePath) async {
  try {
    final saved = await exportHarmonyFile(sourcePath);
    if (saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.general.done)));
    }
  } catch (error) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => ErrorDialog(error: error.toString()),
      );
    }
  }
}
