import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:refena_flutter/refena_flutter.dart';

class VersionData {
  final String version;
  final String buildNumber;
  final String combinedString;

  VersionData({
    required this.version,
    required this.buildNumber,
  }) : combinedString = '$version ($buildNumber)';
}

final versionProvider = FutureProvider((ref) async {
  if (!kIsWeb && Platform.operatingSystem == 'ohos') {
    const channel = MethodChannel('org.localsend.localsend_app/harmony_device');
    try {
      final result = await channel.invokeMapMethod<String, Object>('appVersion');
      return VersionData(version: result?['version'] as String? ?? '—', buildNumber: result?['buildNumber'] as String? ?? '—');
    } catch (_) {
      return VersionData(version: '—', buildNumber: '—');
    }
  }
  final info = await PackageInfo.fromPlatform();
  return VersionData(
    version: info.version,
    buildNumber: info.buildNumber,
  );
}, debugLabel: 'VersionProvider');
