import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'dense overlay is bounded, uses per-image alpha, and clears resources',
    (tester) async {
      late DanmakuController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 450,
            child: DanmakuScreen(
              option: const DanmakuOption(
                maxActiveItems: 3,
                maxFrameRate: 30,
                opacity: 0.4,
                massiveMode: true,
              ),
              createdController: (value) => controller = value,
            ),
          ),
        ),
      );
      for (var i = 0; i < 1000; i++) {
        controller.addDanmaku(DanmakuContentItem('dense $i'));
      }
      expect(controller.scrollDanmaku.length, 3);
      controller.updateOption(controller.option.copyWith(maxActiveItems: 0));
      for (var i = 3; i < 200; i++) {
        controller.addDanmaku(DanmakuContentItem('unlimited $i'));
      }
      expect(controller.scrollDanmaku.length, 200);
      controller.updateOption(controller.option.copyWith(maxActiveItems: 3));
      controller.addDanmaku(DanmakuContentItem('limited again'));
      expect(controller.scrollDanmaku.length, 200);
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(Opacity), findsNothing);
      final items = controller.scrollDanmaku.toList();
      expect(items.every((item) => item.image != null), true);
      controller.clear();
      expect(controller.scrollDanmaku, isEmpty);
      expect(items.every((item) => item.image == null), true);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '30 FPS changes redraw frequency while preserving elapsed-time motion',
    (tester) async {
      late DanmakuController controller;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 450,
            child: DanmakuScreen(
              option: const DanmakuOption(maxFrameRate: 30, duration: 10),
              createdController: (value) => controller = value,
            ),
          ),
        ),
      );
      controller.addDanmaku(DanmakuContentItem('motion'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final item = controller.scrollDanmaku.single;
      final start = item.xPosition;
      await tester.pump(const Duration(milliseconds: 16));
      expect(item.xPosition, start);
      await tester.pump(const Duration(milliseconds: 1000));
      final expectedDistance = (controller.viewWidth + item.width) * 1.016 / 10;
      expect(start - item.xPosition, closeTo(expectedDistance, 0.1));
      controller.pause();
      final paused = item.xPosition;
      await tester.pump(const Duration(seconds: 3));
      controller.resume();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(paused - item.xPosition, lessThan(10));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
