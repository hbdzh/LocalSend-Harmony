import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/util/native/harmony_export.dart';

/// The folder is a picker starting location, not the automatic receive target.
class HarmonyExportFolderSetting extends StatefulWidget {
  const HarmonyExportFolderSetting({super.key});

  @override
  State<HarmonyExportFolderSetting> createState() => _HarmonyExportFolderSettingState();
}

class _HarmonyExportFolderSettingState extends State<HarmonyExportFolderSetting> {
  String? _folder;

  @override
  void initState() {
    super.initState();
    unawaited(
      getHarmonyExportFolder().then((folder) {
        if (mounted) setState(() => _folder = folder);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return ListTile(
      title: Text(chinese ? '导出时优先打开的文件夹' : 'Preferred export folder'),
      subtitle: Text(chinese ? '导出时仍需确认保存位置。' : 'You will still confirm the save location.'),
      trailing: Wrap(
        children: [
          if (_folder != null)
            IconButton(
              tooltip: chinese ? '清除' : 'Clear',
              icon: const Icon(Icons.clear),
              onPressed: () async {
                await clearHarmonyExportFolder();
                if (mounted) setState(() => _folder = null);
              },
            ),
          TextButton(
            onPressed: () async {
              try {
                final folder = await chooseHarmonyExportFolder();
                if (mounted && folder != null) setState(() => _folder = folder);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(chinese ? '无法选择文件夹，请重试。' : 'Could not select the folder.')),
                  );
                }
              }
            },
            child: Text(_folder == null ? (chinese ? '选择' : 'Choose') : (chinese ? '更改' : 'Change')),
          ),
        ],
      ),
    );
  }
}
