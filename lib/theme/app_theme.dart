import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

/// 品牌常量 + 自适应调色板。
/// 页面中与明暗相关的颜色一律走 [AppPalette.of(context)] 取，
/// 它从 Forui 主题（[FTheme]）派生：换肤只改 forui_theme.dart 即可，
/// 这里不做第二套定义，避免两边分叉。
class AppTheme {
  // 主色调 - 清爽的天空蓝
  static const Color primaryBlue = Color(0xFF4FC3F7);
  static const Color deepBlue = Color(0xFF0288D1);
  static const Color skyBlue = Color(0xFFB3E5FC);

  // 辅助色 - 活力橙
  static const Color accentOrange = Color(0xFFFFB74D);
  static const Color warmYellow = Color(0xFFFFE082);

  // 背景色 - 柔和米白
  static const Color bgCream = Color(0xFFFDF8F0);
  static const Color bgWhite = Color(0xFFFFFFFF);

  // 文字色（历史常量保留给固定点缀用；页面正文走 AppPalette）
  static const Color textDark = Color(0xFF37474F);
  static const Color textGrey = Color(0xFF90A4AE);
  static const Color textLight = Color(0xFFB0BEC5);

  // 页面渐变背景（亮/暗）
  static const LinearGradient bgGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFE1F5FE),
      Color(0xFFFDF8F0),
    ],
  );

  // 渐变背景（深色）：深海夜空
  static const LinearGradient bgGradientDark = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0C1524),
      Color(0xFF111B2E),
    ],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF4FC3F7),
      Color(0xFF29B6F6),
    ],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFB74D),
      Color(0xFFFFA726),
    ],
  );
}

/// 自适应调色板：唯一真相源是 Forui 主题，这里只做语义映射。
class AppPalette {
  final Color text;
  final Color sub;
  final Color faint;
  final Color card;
  final Color nav;
  final Color chip;
  final Color strong;
  final Color border;
  final LinearGradient page;
  final Color shadow;
  final bool isDark;

  const AppPalette({
    required this.text,
    required this.sub,
    required this.faint,
    required this.card,
    required this.nav,
    required this.chip,
    required this.strong,
    required this.border,
    required this.page,
    required this.shadow,
    required this.isDark,
  });

  static AppPalette of(BuildContext context) {
    final colors = context.theme.colors;
    if (Theme.of(context).brightness == Brightness.dark) {
      return AppPalette(
        text: colors.foreground,
        sub: colors.mutedForeground,
        faint: colors.mutedForeground.withValues(alpha: 0.6),
        card: colors.card,
        nav: colors.card,
        chip: colors.card.withValues(alpha: 0.7),
        strong: colors.primary,
        border: colors.border,
        page: AppTheme.bgGradientDark,
        shadow: const Color(0x59000000),
        isDark: true,
      );
    }
    return AppPalette(
      text: colors.foreground,
      sub: colors.mutedForeground,
      faint: colors.mutedForeground.withValues(alpha: 0.6),
      card: colors.card,
      nav: colors.card,
      chip: colors.card.withValues(alpha: 0.7),
      strong: colors.primary,
      border: colors.border,
      page: AppTheme.bgGradient,
      shadow: const Color(0x0A000000),
      isDark: false,
    );
  }
}

/// 圆角卡片装饰
class CardDecoration {
  /// 自适应卡片底（取 Forui 的 card/border）。
  static BoxDecoration softOf(
    BuildContext context, {
    double radius = 20,
    Color? borderColor,
  }) {
    final p = AppPalette.of(context);
    return BoxDecoration(
      color: p.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? p.border,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: p.shadow,
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static BoxDecoration gradient({
    LinearGradient? gradient,
    double radius = 20,
  }) {
    return BoxDecoration(
      gradient: gradient ?? AppTheme.cardGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: AppTheme.primaryBlue.withValues(alpha: 0.3),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
