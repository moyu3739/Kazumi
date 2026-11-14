import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:win32/win32.dart';

/// Frame-rate choices exposed by the danmaku settings.
class DanmakuFrameRate {
  DanmakuFrameRate._();

  static const defaultRate = 60;
  static const _standardRates = [30, 60, 75, 90, 120, 144, 165, 240];

  /// Builds standard choices and adds the current physical display rate. The
  /// physical rate is rounded to the nearest whole FPS because the canvas
  /// ticker accepts integer FPS.
  static List<int> options({int? physicalRate}) {
    final rates = <int>{..._standardRates};
    if (physicalRate != null && physicalRate > 0) {
      rates.add(physicalRate);
    }
    return rates.toList()..sort();
  }

  static String label(int rate, {int? physicalRate}) {
    if (physicalRate != null && rate == physicalRate) {
      return '$rate 帧（当前显示器）';
    }
    return '$rate 帧';
  }

  /// Returns the refresh rate of the current display, rounded to FPS.
  ///
  /// Windows is read through EnumDisplaySettings so the result is available
  /// even though screen_retriever's Display model has no refresh-rate field.
  /// Mobile platforms use flutter_displaymode when it is implemented.
  static Future<int?> currentPhysicalRate() async {
    if (Platform.isWindows) return _windowsRefreshRate();
    try {
      final mode = await FlutterDisplayMode.active;
      final rate = mode.refreshRate.round();
      return rate > 0 ? rate : null;
    } catch (_) {
      return null;
    }
  }

  static int? _windowsRefreshRate() {
    try {
      return using((arena) {
        final mode = arena<DEVMODE>()..ref.dmSize = sizeOf<DEVMODE>();
        final result = EnumDisplaySettings(
          nullptr,
          ENUM_CURRENT_SETTINGS,
          mode,
        );
        if (result == 0 || mode.ref.dmDisplayFrequency <= 0) return null;
        return mode.ref.dmDisplayFrequency;
      });
    } catch (_) {
      return null;
    }
  }
}
