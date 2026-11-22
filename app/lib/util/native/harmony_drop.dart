import 'package:flutter/services.dart';

/// Events from the HarmonyOS PC window's system drag target.
class HarmonyDrop {
  static const channel = MethodChannel('org.localsend.localsend_app/harmony_drop');
  static int _generation = 0;

  static int listen({
    required void Function() onEntered,
    required void Function() onExited,
    required Future<bool> Function(List<String> paths, List<String> directories, int failed) onDropped,
  }) {
    final generation = ++_generation;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'entered':
          onEntered();
        case 'exited':
          onExited();
        case 'dropped':
          final payload = Map<Object?, Object?>.from(call.arguments as Map);
          final paths = (payload['paths'] as List).cast<String>();
          final directories = (payload['directories'] as List? ?? const []).cast<String>();
          return await onDropped(paths, directories, payload['failed'] as int);
      }
    });
    return generation;
  }

  static void dispose(int generation) {
    if (generation == _generation) {
      channel.setMethodCallHandler(null);
    }
  }
}
