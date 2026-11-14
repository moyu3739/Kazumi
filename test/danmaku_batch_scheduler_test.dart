import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/danmaku_batch_scheduler.dart';

void main() {
  testWidgets(
    'dense comments are capped, staggered, and a second is emitted once',
    (tester) async {
      final emitted = <int>[];
      final queue = DanmakuBatchScheduler<int>(now: tester.binding.clock.now);
      void schedule(int generation) => queue.schedule(
        second: 12,
        generation: generation,
        items: List.generate(10000, (i) => i),
        maxItems: 24,
        emit: emitted.add,
      );
      schedule(0);
      expect(emitted.length, 1);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(emitted.length, 24);
      schedule(0);
      await tester.pump(const Duration(seconds: 1));
      expect(emitted.length, 24);
      schedule(1);
      expect(emitted.length, 25);
      queue.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(emitted.length, 25);
    },
  );
  testWidgets(
    'a delayed timer drops old comments instead of replaying a burst',
    (tester) async {
      final emitted = <int>[];
      var now = DateTime(2026);
      final queue = DanmakuBatchScheduler<int>(now: () => now);
      queue.schedule(
        second: 1,
        generation: 0,
        items: List.generate(60, (i) => i),
        maxItems: 60,
        emit: emitted.add,
      );
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 25));
      expect(emitted, [0]);
      queue.cancel();
    },
  );

  testWidgets(
    'unlimited mode emits all dense comments and can be limited again',
    (tester) async {
      final emitted = <int>[];
      final queue = DanmakuBatchScheduler<int>(now: tester.binding.clock.now);
      queue.schedule(
        second: 1,
        generation: 0,
        items: List.generate(1000, (i) => i),
        maxItems: 0,
        emit: emitted.add,
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(emitted, List.generate(1000, (i) => i));
      emitted.clear();
      queue.schedule(
        second: 2,
        generation: 0,
        items: List.generate(1000, (i) => i),
        maxItems: 24,
        emit: emitted.add,
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 25));
      }
      expect(emitted.length, 24);
      queue.cancel();
    },
  );

  testWidgets(
    'unlimited mode does not discard comments after a delayed timer',
    (tester) async {
      final emitted = <int>[];
      var now = DateTime(2026);
      final queue = DanmakuBatchScheduler<int>(now: () => now);
      queue.schedule(
        second: 1,
        generation: 0,
        items: List.generate(1000, (i) => i),
        maxItems: 0,
        emit: emitted.add,
      );
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 25));
      expect(emitted, List.generate(1000, (i) => i));
      queue.cancel();
    },
  );
}
