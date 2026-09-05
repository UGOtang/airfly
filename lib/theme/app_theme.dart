import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 日式少年风格主题：浅色 + 暗夜两套。
/// 页面中与明暗相关的颜色一律走 [AppPalette.of(context)] 取，
/// 品牌色（天空蓝/活力橙）两套主题共用，保证识别一致。
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

  // 文字色（浅色主题用；深色主题用 AppPalette.dark）
  static const Color textDark = Color(0xFF37474F);
  static const Color textGrey = Color(0xFF90A4AE);
  static const Color textLight = Color(0xFFB0BEC5);

  // 渐变背景（浅色）
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

  // ---------------- 浅色主题

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        primary: primaryBlue,
        secondary: accentOrange,
        surface: bgWhite,
      ),
      scaffoldBackgroundColor: bgCream,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, textDark, textGrey),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: textDark),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: bgWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      filledButtonTheme: _filledButtonTheme(),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE1F5FE),
        selectedColor: primaryBlue,
        labelStyle: const TextStyle(color: textDark, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide.none,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bgWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: const TextStyle(
          color: textDark,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: textGrey,
          fontSize: 15,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bgWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryBlue,
        linearTrackColor: Color(0xFFE1F5FE),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFECEFF1),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: _inputTheme(
        fill: const Color(0xFFF5F5F5),
        hint: textGrey,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: deepBlue,
        unselectedLabelColor: textGrey,
        indicatorColor: primaryBlue,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: primaryBlue,
        textColor: textDark,
      ),
    );
  }

  // ---------------- 深色主题

  static const Color _darkBg = Color(0xFF0E1522);
  static const Color _darkCard = Color(0xFF1A2334);
  static const Color _darkText = Color(0xFFE9EFF6);
  static const Color _darkSub = Color(0xFF9AA9BC);
  static const Color _darkStrong = Color(0xFF7FD0F7);

  static ThemeData get darkTheme {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
        primary: primaryBlue,
        secondary: accentOrange,
        surface: _darkCard,
      ),
      scaffoldBackgroundColor: _darkBg,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme, _darkText, _darkSub),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: _darkText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: _darkText),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: _darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(
            color: Color(0x14FFFFFF),
            width: 1,
          ),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: _elevatedButtonTheme(),
      filledButtonTheme: _filledButtonTheme(),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFF24304A),
        selectedColor: primaryBlue,
        labelStyle: const TextStyle(color: _darkText, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide.none,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _darkText,
        contentTextStyle: const TextStyle(color: Color(0xFF1A2334)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(
            color: Color(0x14FFFFFF),
            width: 1,
          ),
        ),
        titleTextStyle: const TextStyle(
          color: _darkText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: _darkSub,
          fontSize: 15,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryBlue,
        linearTrackColor: Color(0xFF24304A),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF26314A),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: _inputTheme(
        fill: const Color(0xFF141D2E),
        hint: _darkSub,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: _darkStrong,
        unselectedLabelColor: _darkSub,
        indicatorColor: primaryBlue,
        labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: primaryBlue,
        textColor: _darkText,
      ),
    );
  }

  // ---------------- 共用部件

  static TextTheme _textTheme(TextTheme base, Color text, Color sub) {
    return base.copyWith(
      displaySmall: TextStyle(
        color: text,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineMedium: TextStyle(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        color: text,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: text,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(
        color: text,
        fontSize: 16,
      ),
      bodyMedium: TextStyle(
        color: sub,
        fontSize: 14,
      ),
      labelLarge: const TextStyle(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static InputDecorationTheme _inputTheme({
    required Color fill,
    required Color hint,
  }) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      hintStyle: TextStyle(color: hint),
      labelStyle: TextStyle(color: hint),
      prefixIconColor: hint,
      suffixIconColor: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: primaryBlue, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

/// 自适应调色板：页面里所有随明暗变化的颜色都从这里取，
/// 不要再直接引用 AppTheme.textDark / bgWhite 等固定值。
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
  });

  static const light = AppPalette(
    text: AppTheme.textDark,
    sub: AppTheme.textGrey,
    faint: AppTheme.textLight,
    card: AppTheme.bgWhite,
    nav: AppTheme.bgWhite,
    chip: Color(0xB3FFFFFF),
    strong: AppTheme.deepBlue,
    border: Color(0x00000000),
    page: AppTheme.bgGradient,
    shadow: Color(0x0A000000),
  );

  static const dark = AppPalette(
    text: Color(0xFFE9EFF6),
    sub: Color(0xFF9AA9BC),
    faint: Color(0xFF5F7186),
    card: Color(0xFF1A2334),
    nav: Color(0xFF141C2A),
    chip: Color(0xB31A2334),
    strong: Color(0xFF7FD0F7),
    border: Color(0x14FFFFFF),
    page: AppTheme.bgGradientDark,
    shadow: Color(0x59000000),
  );

  static AppPalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  bool get isDark => this == dark;
}

/// 圆角卡片装饰
class CardDecoration {
  /// 自适应卡片底（浅色白卡 / 深色 navy 卡 + 细边框）。
  static BoxDecoration softOf(
    BuildContext context, {
    double radius = 20,
    Color? borderColor,
  }) {
    final p = AppPalette.of(context);
    return BoxDecoration(
      color: p.card,
      borderRadius: BorderRadius.circular(radius),
      border: borderColor != null
          ? Border.all(color: borderColor, width: 1)
          : Border.all(color: p.border, width: 1),
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
