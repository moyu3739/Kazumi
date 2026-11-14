import 'package:canvas_danmaku/base_danmaku_painter.dart';
import 'package:canvas_danmaku/models/danmaku_content_item.dart';
import 'package:canvas_danmaku/models/danmaku_item.dart';
import 'package:flutter/material.dart';

final class StaticDanmakuPainter extends CustomPainter {
  final int length;
  final List<DanmakuItem> danmakuItems;
  final double staticDurationInMilliseconds;
  final double fontSize;
  final int fontWeight;
  final double strokeWidth;
  final double devicePixelRatio;
  final int tick;
  final double opacity;

  StaticDanmakuPainter({
    required this.length,
    required this.danmakuItems,
    required this.staticDurationInMilliseconds,
    required this.fontSize,
    required this.fontWeight,
    required this.strokeWidth,
    required this.devicePixelRatio,
    required this.tick,
    this.opacity = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var item in danmakuItems) {
      item
        ..drawTick ??= tick
        ..drawParagraphIfNeeded(
          fontSize,
          fontWeight,
          strokeWidth,
          devicePixelRatio,
        )
        ..xPosition = (size.width - item.width) / 2;

      BaseDanmakuPainter.paintImg(
        canvas,
        item,
        item.xPosition,
        item.content.type == DanmakuItemType.bottom
            ? size.height - item.yPosition - item.height
            : item.yPosition,
        devicePixelRatio,
        opacity,
      );
    }
  }

  @override
  bool shouldRepaint(covariant StaticDanmakuPainter oldDelegate) =>
      oldDelegate.length != length ||
      oldDelegate.opacity != opacity ||
      oldDelegate.tick != tick ||
      oldDelegate.fontSize != fontSize ||
      oldDelegate.fontWeight != fontWeight ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
