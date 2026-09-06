// AirFly 主题：直接使用 Forui 原生 neutral 主题（亮/暗）。
// 不做颜色覆盖——Forui 的 IMPACT 在于整体一致性，品牌天空蓝保留在
// 点缀位（标题徽标、状态点、头像、进度条），由各页面直接取用 AppTheme 常量。
// 移动端用 touch 版式、桌面端用 desktop 版式（照官方推荐）。
// Material 侧通过 toApproximateMaterialTheme() 自动派生，保持混用一致。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 暗夜品牌主色（浅天蓝）上的前景深海军蓝，保证对比度。
/// 亮/暗品牌主色本身复用 AppTheme.deepBlue / AppTheme.primaryBlue。
const Color kBrandDarkFg = Color(0xFF06222F);

bool _isTouchPlatform() {
  if (kIsWeb) return false;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.fuchsia:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return false;
  }
}

FThemeData airFlyTheme(Brightness brightness) {
  final touch = _isTouchPlatform();
  final neutral = FTheme.neutral;
  if (brightness == Brightness.dark) {
    return touch ? neutral.dark.touch : neutral.dark.desktop;
  }
  return touch ? neutral.light.touch : neutral.light.desktop;
}

ThemeData airFlyMaterial(Brightness brightness) =>
    airFlyTheme(brightness).toApproximateMaterialTheme();
