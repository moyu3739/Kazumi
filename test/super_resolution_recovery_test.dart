import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_super_resolution.dart';
import 'package:kazumi/services/player/super_resolution_recovery.dart';

void main() {
  late DateTime now;
  late List<SuperResolutionMode> writes;
  late SuperResolutionRecovery guard;
  var frames = 0;
  Future<void> step({bool fresh = true, bool eligible = true}) async {
    now = now.add(const Duration(milliseconds: 250));
    if (fresh) frames++;
    await guard.sample(eligible: eligible, presentedFrames: frames,
        presentedAgeMs: fresh ? 0 : 800,
        position: Duration(milliseconds: now.millisecondsSinceEpoch));
  }
  setUp(() {
    now = DateTime(2026);
    frames = 0;
    writes = [];
    guard = SuperResolutionRecovery(initialMode: SuperResolutionMode.quality,
        now: () => now, apply: (mode) async { writes.add(mode); }, onEvent: (_) {});
  });
  test('real output stall bypasses temporarily and restores the chosen quality', () async {
    for (var i = 0; i < 12; i++) { await step(); }
    for (var i = 0; i < 3; i++) { await step(fresh: false); }
    expect(writes, [SuperResolutionMode.off]);
    expect(guard.requested, SuperResolutionMode.quality);
    for (var i = 0; i < 10; i++) { await step(); }
    expect(writes, [SuperResolutionMode.off, SuperResolutionMode.quality]);
    expect(guard.bypassed, false);
  });
  test('no bypass for pause, buffering, seek grace, or healthy output', () async {
    for (var i = 0; i < 30; i++) { await step(); }
    for (var i = 0; i < 20; i++) { await step(fresh: false, eligible: false); }
    for (var i = 0; i < 5; i++) { await step(fresh: false); }
    guard.resetObservation();
    for (var i = 0; i < 5; i++) { await step(fresh: false); }
    expect(writes, isEmpty);
  });
  test('user disabling SR during a pending bypass wins over automatic restore', () async {
    final pending = Completer<void>();
    guard = SuperResolutionRecovery(initialMode: SuperResolutionMode.quality,
        now: () => now, onEvent: (_) {}, apply: (mode) async {
          writes.add(mode);
          await pending.future;
        });
    for (var i = 0; i < 12; i++) { await step(); }
    await step(fresh: false);
    final bypass = step(fresh: false);
    await Future<void>.delayed(Duration.zero);
    final userOff = guard.setMode(SuperResolutionMode.off);
    pending.complete();
    await Future.wait([bypass, userOff]);
    for (var i = 0; i < 150; i++) { await step(); }
    expect(guard.requested, SuperResolutionMode.off);
    expect(writes, [SuperResolutionMode.off]);
  });
  test('mode changes are coalesced and stale writes cannot restore old choice', () async {
    final pending = Completer<void>();
    var active = 0;
    guard = SuperResolutionRecovery(initialMode: SuperResolutionMode.off,
        now: () => now, onEvent: (_) {}, apply: (mode) async {
          expect(++active, 1);
          writes.add(mode);
          if (writes.length == 1) await pending.future;
          active--;
        });
    final first = guard.setMode(SuperResolutionMode.quality);
    await Future<void>.delayed(Duration.zero);
    final second = guard.setMode(SuperResolutionMode.efficiency);
    final third = guard.setMode(SuperResolutionMode.off);
    pending.complete();
    await Future.wait([first, second, third]);
    expect(writes, [SuperResolutionMode.quality, SuperResolutionMode.off]);
    expect(guard.effective, SuperResolutionMode.off);
  });
  test('bypass always retries within 30 seconds even if it did not help', () async {
    for (var i = 0; i < 12; i++) { await step(); }
    for (var i = 0; i < 3; i++) { await step(fresh: false); }
    for (var i = 0; i < 120; i++) { await step(fresh: false); }
    expect(writes.take(2), [SuperResolutionMode.off, SuperResolutionMode.quality]);
  });
  test('dispose during shader write prevents subsequent restore', () async {
    final pending = Completer<void>();
    guard = SuperResolutionRecovery(initialMode: SuperResolutionMode.off,
        now: () => now, onEvent: (_) {}, apply: (mode) async {
          writes.add(mode);
          await pending.future;
        });
    final first = guard.setMode(SuperResolutionMode.quality);
    await Future<void>.delayed(Duration.zero);
    final second = guard.setMode(SuperResolutionMode.efficiency);
    guard.dispose();
    pending.complete();
    await Future.wait([first, second]);
    expect(writes, [SuperResolutionMode.quality]);
  });
  test('shader failures do not create an unbounded command queue', () async {
    var attempts = 0;
    guard = SuperResolutionRecovery(initialMode: SuperResolutionMode.quality,
        now: () => now, onEvent: (_) {}, apply: (_) async {
          attempts++;
          throw StateError('simulated MPV failure');
        });
    for (var i = 0; i < 12; i++) { await step(); }
    for (var i = 0; i < 50; i++) {
      try { await step(fresh: false); } catch (_) {}
    }
    expect(attempts, lessThanOrEqualTo(8));
    expect(guard.requested, SuperResolutionMode.quality);
  });
}
