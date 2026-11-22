import 'package:flutter/material.dart';
import 'package:localsend_app/util/native/harmony_window.dart';

/// HarmonyOS exposes the status; the user changes it in system settings.
class HarmonyStartupSetting extends StatefulWidget {
  const HarmonyStartupSetting({super.key});

  @override
  State<HarmonyStartupSetting> createState() => _HarmonyStartupSettingState();
}

class _HarmonyStartupSettingState extends State<HarmonyStartupSetting> with WidgetsBindingObserver {
  late Future<({bool supported, bool? enabled})> _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = HarmonyWindow.autoStartupStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _status = HarmonyWindow.autoStartupStatus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return FutureBuilder<({bool supported, bool? enabled})>(
      future: _status,
      builder: (context, snapshot) {
        final status = snapshot.data;
        final text = snapshot.hasError
            ? (chinese ? '无法查询' : 'Unavailable')
            : status == null
            ? (chinese ? '查询中' : 'Checking')
            : !status.supported
            ? (chinese ? '此设备不支持查询' : 'Status not supported')
            : status.enabled == true
            ? (chinese ? '已开启' : 'Enabled')
            : (chinese ? '未开启' : 'Disabled');
        return ListTile(
          title: Text(chinese ? '开机自启动：$text' : 'Start at login: $text'),
          subtitle: Text(chinese ? '请在系统设置的“应用启动管理”中更改。' : 'Change this in system app launch settings.'),
          trailing: IconButton(tooltip: chinese ? '刷新' : 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh)),
        );
      },
    );
  }
}
