import 'dart:io';

import 'package:path/path.dart' as p;

/// Tracks paths that may contain incomplete receives. The data file is never
/// removed here: another process may have replaced it or it may be complete.
class HarmonyReceiveRecovery {
  static Directory _root(String cache) => Directory(p.join(cache, 'localsend-unfinished-receives'));

  static File record(String cache, String path) {
    final root = _root(cache)..createSync(recursive: true);
    final dir = root.createTempSync('receive-');
    final marker = File(p.join(dir.path, 'active'));
    marker.writeAsStringSync(path, flush: true);
    return marker;
  }

  static File markFailed(File marker) => marker.renameSync(p.join(marker.parent.path, 'path'));

  static List<(File, String)> pending(String cache, {bool includeActive = false}) {
    final root = _root(cache);
    if (!root.existsSync()) return [];
    final result = <(File, String)>[];
    for (final dir in root.listSync(followLinks: false).whereType<Directory>()) {
      final marker = File(p.join(dir.path, 'path'));
      if (marker.existsSync()) result.add((marker, marker.readAsStringSync()));
      final active = File(p.join(dir.path, 'active'));
      if (includeActive && active.existsSync()) result.add((active, active.readAsStringSync()));
    }
    return result;
  }

  static void forget(File marker) {
    marker.deleteSync();
    marker.parent.deleteSync();
  }
}
