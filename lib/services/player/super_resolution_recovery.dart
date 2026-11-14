import 'package:kazumi/pages/player/controller/player_super_resolution.dart';

/// Recovers from output stalls without changing the user's requested mode.
/// This bypasses future shader work; it cannot cancel work already on the GPU.
class SuperResolutionRecovery {
  SuperResolutionRecovery({
    required SuperResolutionMode initialMode,
    SuperResolutionMode? initialEffective,
    required this.apply,
    required this.onEvent,
    DateTime Function()? now,
  }) : requested = initialMode,
       effective = initialEffective ?? initialMode,
       _now = now ?? DateTime.now;

  final Future<void> Function(SuperResolutionMode) apply;
  final void Function(String) onEvent;
  final DateTime Function() _now;
  SuperResolutionMode requested;
  SuperResolutionMode effective;
  bool bypassed = false;
  bool _disposed = false;
  Future<void>? _writing;
  DateTime? _eligibleSince;
  DateTime? _lastFrameAt;
  DateTime? _lastPositionAt;
  DateTime? _healthySince;
  DateTime? _bypassedAt;
  DateTime? _retryAt;
  int? _frames;
  Duration? _position;
  int _failures = 0;

  SuperResolutionMode get _wanted =>
      bypassed ? SuperResolutionMode.off : requested;

  Future<void> ensureApplied() => _reconcile();

  Future<void> setMode(SuperResolutionMode mode) {
    requested = mode;
    bypassed = false;
    _failures = 0;
    resetObservation();
    return _reconcile();
  }

  void resetObservation() {
    _eligibleSince = null;
    _lastFrameAt = null;
    _lastPositionAt = null;
    _healthySince = null;
    _position = null;
    _frames = null;
  }

  Future<void> _reconcile() {
    if (_disposed) return Future.value();
    if (_writing != null) return _writing!;
    // The microtask also ensures _writing is installed before apply runs.
    return _writing = Future<void>.microtask(() async {
      try {
        while (!_disposed && effective != _wanted) {
          final target = _wanted;
          await apply(target);
          if (_disposed) return;
          effective = target;
        }
      } finally {
        _writing = null;
      }
    });
  }

  Future<void> sample({
    required bool eligible,
    required int presentedFrames,
    required int presentedAgeMs,
    required Duration position,
  }) async {
    if (_disposed) return;
    final now = _now();
    if (!eligible || requested == SuperResolutionMode.off) {
      resetObservation();
      return;
    }
    _eligibleSince ??= now;
    final previousPosition = _position;
    if (previousPosition != null &&
        (position < previousPosition ||
            (position - previousPosition).inMilliseconds > 2000)) {
      resetObservation();
      _eligibleSince = now;
    }
    if (position != _position) _lastPositionAt = now;
    _position = position;
    if (_frames != presentedFrames) {
      _lastFrameAt = now;
      _frames = presentedFrames;
    }
    _lastFrameAt ??= now;
    final fresh =
        presentedFrames > 0 &&
        presentedAgeMs >= 0 &&
        presentedAgeMs < 300 &&
        now.difference(_lastFrameAt!).inMilliseconds < 500;
    if (fresh) {
      _healthySince ??= now;
    } else {
      _healthySince = null;
    }
    if (_writing != null) return;
    if (bypassed) {
      final stable =
          _healthySince != null &&
          now.difference(_healthySince!).inMilliseconds >= 1500;
      // Even if bypass did not help, retry SR within 30 seconds. There is no
      // permanent automatic-off state or settings write in this controller.
      final deadline =
          _bypassedAt != null && now.difference(_bypassedAt!).inSeconds >= 30;
      if ((stable && !now.isBefore(_retryAt!)) || deadline) {
        bypassed = false;
        resetObservation();
        onEvent(
          'retry ${requested.name}; frames=$presentedFrames age=${presentedAgeMs}ms',
        );
        await _reconcile();
      } else if (effective != _wanted && !now.isBefore(_retryAt!)) {
        // A failed shader write is retried at a bounded rate.
        _retryAt = now.add(const Duration(seconds: 2));
        await _reconcile();
      }
      return;
    }
    if (_healthySince != null &&
        now.difference(_healthySince!).inSeconds >= 30) {
      _failures = 0;
    }
    final audioAdvancing =
        _lastPositionAt != null &&
        now.difference(_lastPositionAt!).inMilliseconds < 1500;
    if (now.difference(_eligibleSince!).inSeconds >= 2 &&
        audioAdvancing &&
        now.difference(_lastFrameAt!).inMilliseconds >= 500 &&
        !fresh) {
      bypassed = true;
      _bypassedAt = now;
      final delay = (2 * (1 << _failures.clamp(0, 4))).clamp(2, 30);
      _failures++;
      _retryAt = now.add(Duration(seconds: delay));
      _healthySince = null;
      onEvent(
        'temporary bypass ${requested.name}; frames=$presentedFrames '
        'age=${presentedAgeMs}ms; retry after ${delay}s',
      );
      await _reconcile();
    } else if (effective != _wanted) {
      // E.g. a restore failed. Keep retrying without accumulating commands.
      _retryAt ??= now;
      if (!now.isBefore(_retryAt!)) {
        _retryAt = now.add(const Duration(seconds: 2));
        await _reconcile();
      }
    }
  }

  void dispose() {
    _disposed = true;
    resetObservation();
  }
}
