import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:localsend_isolates/util/file_size_helper.dart';
import 'package:localsend_isolates/util/file_speed_helper.dart';
import 'package:localsend_isolates/util/foreground_service.dart';
import 'package:localsend_isolates/util/future_queue.dart';
import 'package:localsend_isolates/util/notification_strings.dart';
import 'package:logging/logging.dart';

/// A transfer only becomes fast enough to measure after a while; the first chunks are not
/// representative. Same threshold as `ProgressPage`.
const _minBytesForSpeed = 500 * 1024;

/// Drives the single foreground service notification on behalf of all running transfers.
///
/// There is one notification but there can be several transfers: receiving is limited to one
/// session, sending is not, and both directions can run at the same time. So the service is
/// reference counted here - it starts with the first transfer, ends with the last one, and the
/// notification shows the sum of everything in flight.
class TransferNotification {
  TransferNotification._();

  static final _transfers = <String, _Transfer>{};
  static bool get hasActiveTransfers => _transfers.isNotEmpty;
  static NotificationStrings? _strings;
  static const _harmonyChannel = MethodChannel('org.localsend.localsend_app/harmony_background');
  static final _harmonyQueue = FutureQueue(onError: (e, st) => Logger('HarmonyBackground').warning('Background task failed', e, st));

  @visibleForTesting
  static bool? harmonyOverride;
  static bool get _isHarmony => harmonyOverride ?? Platform.operatingSystem == 'ohos';

  /// True when the most recent background-task operation could not be completed.
  static final ValueNotifier<bool> harmonyBackgroundUnavailable = ValueNotifier(false);
  static bool _harmonyStarted = false;
  static bool _harmonyProgressPublished = false;
  static int _harmonyStartsPending = 0;
  static int _harmonyCancellation = 0;

  /// True after the current task starts and its progress notification is published.
  static bool get harmonyBackgroundReady =>
      _harmonyStartsPending == 0 && _harmonyStarted && _harmonyProgressPublished && !harmonyBackgroundUnavailable.value;
  static void _harmonyTask(String method, [Map<String, Object>? arguments]) {
    if (!_isHarmony) return;
    if (method == 'start') _harmonyStartsPending++;
    // Serialize lifecycle calls so a slow start cannot finish after the final stop.
    _harmonyQueue.add(() async {
      if (method == 'progress' && !_harmonyStarted) return;
      final cancellation = _harmonyCancellation;
      try {
        await _harmonyChannel.invokeMethod<void>(method, arguments);
        if (cancellation != _harmonyCancellation) return;
        if (method == 'start') {
          _harmonyStarted = true;
          _harmonyProgressPublished = false;
        } else if (method == 'progress') {
          _harmonyProgressPublished = true;
        } else if (method == 'stop') {
          _harmonyStarted = false;
          _harmonyProgressPublished = false;
        }
        harmonyBackgroundUnavailable.value = false;
      } catch (error, stack) {
        if (method == 'start' || method == 'stop' || (error is PlatformException && error.code == 'background_task_missing')) {
          _harmonyStarted = false;
          _harmonyProgressPublished = false;
        }
        harmonyBackgroundUnavailable.value = true;
        Logger('HarmonyBackground').warning('Background task $method failed', error, stack);
      } finally {
        if (method == 'start') _harmonyStartsPending--;
      }
    });
  }

  static void _harmonyProgress() {
    if (!_isHarmony || _transfers.isEmpty) return;
    final current = _transfers.values.fold<int>(0, (sum, item) => sum + item.currentBytes);
    final total = _transfers.values.fold<int>(0, (sum, item) => sum + item.totalBytes);
    final progress = total <= 0 ? 0 : (100 * current ~/ total).clamp(0, 99);
    _harmonyTask('progress', {'title': _title(), 'text': _text(), 'progress': progress});
  }

  /// Injects the translated strings. Must be called before the first transfer starts.
  /// The locale is pinned on app start, so one call is enough.
  static void init(NotificationStrings strings) {
    _strings = strings;
    if (_isHarmony) {
      _harmonyChannel.setMethodCallHandler((call) async {
        if (call.method == 'cancelled' && _transfers.isNotEmpty) {
          _harmonyCancellation++;
          _harmonyStarted = false;
          _harmonyProgressPublished = false;
          harmonyBackgroundUnavailable.value = true;
        }
      });
    }
  }

  /// Request background execution again after the user returns to the app.
  static void retryHarmonyBackground() {
    if (!_isHarmony || _transfers.isEmpty || _harmonyStartsPending != 0) return;
    _harmonyTask('start');
    _harmonyProgress();
  }

  /// Whether [update] would reach the notification, so that callers can skip summing up the
  /// progress of every file for an update that gets throttled away.
  ///
  /// While several transfers run, they take turns passing this check, which means each of them
  /// refreshes its share of the total a bit less often. The numbers stay close enough: every
  /// running transfer reports progress continuously.
  static bool shouldUpdateSession(String sessionId) {
    if (_isHarmony) {
      final transfer = _transfers[sessionId];
      if (transfer == null) return false;
      final last = transfer.lastUpdate;
      return last == null || DateTime.now().difference(last) >= const Duration(seconds: 1);
    }
    return ForegroundService.shouldUpdateNotification;
  }

  /// Registers a transfer, starting the service if it is the first one.
  ///
  /// Must be called while the app is in the foreground: Android 12+ rejects starting a foreground
  /// service from the background.
  static void start({required String sessionId, required bool receiving}) {
    if (_transfers.containsKey(sessionId)) {
      return;
    }

    final isFirst = _transfers.isEmpty;
    _transfers[sessionId] = _Transfer(receiving: receiving);

    if (isFirst) {
      _harmonyTask('start');
      _harmonyProgress();
      ForegroundService.start(
        channelName: _requiredStrings.titleReceiving,
        title: _title(),
        text: _text(),
      );
    }
  }

  /// Reports the progress of a single transfer and refreshes the notification.
  /// Unknown sessions are ignored, so a late progress event cannot revive a finished transfer.
  static void update({
    required String sessionId,
    required int currentBytes,
    required int totalBytes,
    required int? startTime,
    required int? endTime,
  }) {
    final transfer = _transfers[sessionId];
    if (transfer == null) {
      return;
    }

    transfer.lastUpdate = DateTime.now();
    transfer.currentBytes = currentBytes;
    transfer.totalBytes = totalBytes;
    transfer.speedInBytes = _speed(currentBytes: currentBytes, startTime: startTime, endTime: endTime);

    _harmonyProgress();
    ForegroundService.updateNotification(title: _title(), text: _text());
  }

  /// Unregisters a transfer, stopping the service once the last one is gone.
  static void stop(String sessionId) {
    if (_transfers.remove(sessionId) == null) {
      return;
    }

    if (_transfers.isEmpty) {
      _harmonyTask('stop');
      ForegroundService.stop();
    } else {
      _harmonyProgress();
      ForegroundService.updateNotification(title: _title(), text: _text());
    }
  }

  /// The transfer speed in bytes per second, or null while it cannot be measured yet.
  static int? _speed({required int currentBytes, required int? startTime, required int? endTime}) {
    if (startTime == null || currentBytes < _minBytesForSpeed) {
      return null;
    }

    final end = endTime ?? DateTime.now().millisecondsSinceEpoch;
    if (end <= startTime) {
      // guards the division in [getFileSpeed]
      return null;
    }

    return getFileSpeed(start: startTime, end: end, bytes: currentBytes);
  }

  static NotificationStrings get _requiredStrings {
    final strings = _strings;
    if (strings == null) {
      throw StateError('TransferNotification.init() must be called before a transfer starts');
    }
    return strings;
  }

  static String _title() {
    final receiving = _transfers.values.any((transfer) => transfer.receiving);
    final sending = _transfers.values.any((transfer) => !transfer.receiving);
    final strings = _requiredStrings;

    if (receiving && sending) {
      return '${strings.titleReceiving} · ${strings.titleSending}';
    }
    return receiving ? strings.titleReceiving : strings.titleSending;
  }

  /// The combined progress of all running transfers:
  /// 42% (1.2 MB / 3.4 MB)
  /// 0:45 · 1.2 MB/s
  static String _text() {
    int currentBytes = 0;
    int totalBytes = 0;
    int? speedInBytes;
    for (final transfer in _transfers.values) {
      currentBytes += transfer.currentBytes;
      totalBytes += transfer.totalBytes;
      final speed = transfer.speedInBytes;
      if (speed != null) {
        speedInBytes = (speedInBytes ?? 0) + speed;
      }
    }

    final percentage = totalBytes == 0 ? 0 : (100 * currentBytes / totalBytes).floor();
    final text = StringBuffer('$percentage% (${currentBytes.asReadableFileSize} / ${totalBytes.asReadableFileSize})');

    if (speedInBytes != null) {
      text.write('\n${getRemainingTime(bytesPerSeconds: speedInBytes, remainingBytes: totalBytes - currentBytes, strings: _requiredStrings)}');
      text.write(' · ${speedInBytes.asReadableFileSize}/s');
    }

    return text.toString();
  }
}

class _Transfer {
  final bool receiving;
  int currentBytes = 0;
  int totalBytes = 0;
  int? speedInBytes;
  DateTime? lastUpdate;

  _Transfer({required this.receiving});
}
