import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/danmaku_frame_rate.dart';

void main() {
  test('includes standard rates and the physical display rate', () {
    final rates = DanmakuFrameRate.options(physicalRate: 143);

    expect(rates, containsAll(<int>[30, 60, 75, 90, 120, 143]));
    expect(rates, containsAll(<int>[144, 165, 240]));
  });

  test('keeps the higher choices when the display rate is unavailable', () {
    expect(
      DanmakuFrameRate.options(),
      containsAll(<int>[30, 60, 75, 90, 120, 144, 165, 240]),
    );
  });

  test('labels the physical display rate', () {
    expect(DanmakuFrameRate.label(144, physicalRate: 144), '144 帧（当前显示器）');
  });
}
