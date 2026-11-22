import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Coalesces the multiple system events produced by one network transition.
class HarmonyNetwork {
  static const channel = MethodChannel('org.localsend.localsend_app/harmony_network');
  static Timer? _debounce;
  static bool _refreshing = false;
  static bool _refreshPending = false;
  static Future<void> Function()? _refresh;

  static Future<void> _runRefresh([Future<void> Function()? initial]) async {
    if (_refreshing) {
      _refreshPending = true;
      return;
    }
    _refreshing = true;
    try {
      do {
        _refreshPending = false;
        try {
          await (initial ?? _refresh)?.call();
        } catch (error, stack) {
          Logger('HarmonyNetwork').warning('Network refresh failed', error, stack);
        }
        initial = null;
      } while (_refreshPending);
    } finally {
      _refreshing = false;
    }
  }

  /// Serializes the startup IP lookup with later network-change refreshes.
  static Future<void> refreshInitially(Future<void> Function() refresh) => _runRefresh(refresh);

  static Future<void> start(Future<void> Function() refresh) async {
    _refresh = refresh;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'changed') return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () => unawaited(_runRefresh()));
    });
    await channel.invokeMethod<void>('start');
  }
}
