import 'dart:async';

/// One timer instead of one delayed Future per comment. In limited mode a late
/// timer drops expired comments instead of replaying a burst after a blocked frame.
class DanmakuBatchScheduler<T> {
  DanmakuBatchScheduler({DateTime Function()? now})
    : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  Timer? _timer;
  int? _second;
  int? _generation;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void schedule({
    required int second,
    required int generation,
    required Iterable<T> items,
    // Zero disables all quantity and late-batch dropping limits.
    required int maxItems,
    required void Function(T) emit,
  }) {
    if (_second == second && _generation == generation) return;
    cancel();
    _second = second;
    _generation = generation;
    final limited = maxItems > 0;
    final candidates = (limited ? items.take(512) : items).toList(
      growable: false,
    );
    if (candidates.isEmpty || maxItems < 0) return;
    final count = limited
        ? candidates.length.clamp(0, maxItems)
        : candidates.length;
    final batch = List.generate(
      count,
      (i) => candidates[i * candidates.length ~/ count],
    );
    final started = _now();
    var index = 0;
    void drain() {
      final elapsed = _now().difference(started).inMilliseconds;
      var emitted = 0;
      while (index < count && index * 1000 ~/ count <= elapsed) {
        final due = index * 1000 ~/ count;
        final item = batch[index++];
        if (!limited || (elapsed - due <= 200 && emitted < 2)) {
          emit(item);
          emitted++;
        }
      }
      if (index == count) cancel();
    }

    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) => drain());
    drain();
  }
}
