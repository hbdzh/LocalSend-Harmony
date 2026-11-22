import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/util/native/harmony_receive_folder.dart';

class HarmonyReceiveFolderSetting extends StatefulWidget {
  const HarmonyReceiveFolderSetting({super.key});

  @override
  State<HarmonyReceiveFolderSetting> createState() => _HarmonyReceiveFolderSettingState();
}

class _HarmonyReceiveFolderSettingState extends State<HarmonyReceiveFolderSetting> {
  String? _folder;

  @override
  void initState() {
    super.initState();
    unawaited(
      getHarmonyReceiveFolder().then((folder) {
        if (mounted) setState(() => _folder = folder);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return ListTile(
      title: Text(chinese ? '接收文件夹' : 'Receive folder'),
      subtitle: Text(_folder == null ? (chinese ? '默认保存在应用内' : 'Saved in the app by default') : Uri.decodeComponent(_folder!.split('/').last)),
      trailing: Wrap(
        children: [
          if (_folder != null)
            IconButton(
              tooltip: chinese ? '恢复默认' : 'Reset',
              icon: const Icon(Icons.clear),
              onPressed: () async {
                try {
                  await clearHarmonyReceiveFolder();
                  if (mounted) setState(() => _folder = null);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chinese ? '无法清除授权' : 'Could not revoke access')));
                  }
                }
              },
            ),
          TextButton(
            onPressed: () async {
              try {
                final folder = await chooseHarmonyReceiveFolder();
                if (mounted && folder != null) setState(() => _folder = folder);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(chinese ? '文件夹未授权或不可写' : 'Folder access or write check failed')));
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
