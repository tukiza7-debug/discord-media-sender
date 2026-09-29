import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Token rekabentuk aplikasi — satu sumber kebenaran untuk warna, ruang,
/// radius, dan animasi. SEMUA widget mesti merujuk token ini.
class AppColors {
  AppColors._();

  // Aksen utama
  static const blurple = Color(0xFF5865F2);
  static const blurpleDark = Color(0xFF4752C4);
  static const blurpleBright = Color(0xFF8B93FF);

  // Neutral gelap (mod gelap — lalai)
  static const bg = Color(0xFF1E1F22);
  static const surface = Color(0xFF2B2D31);
  static const surfaceHigh = Color(0xFF313338);
  static const overlay = Color(0xFF232428);
  static const outline = Color(0xFF3F4147);

  // Teks
  static const textPrimary = Color(0xFFF2F3F5);
  static const textSecondary = Color(0xFFB5BAC1);
  static const textFaint = Color(0xFF80848E);

  // Status
  static const success = Color(0xFF23A559);
  static const warning = Color(0xFFF0B232);
  static const danger = Color(0xFFF23F43);
  static const info = Color(0xFF00A8FC);

  // Warna teks di atas aksen blurple
  static const onBlurple = Color(0xFFFFFFFF);

  // Konsol (terminal gelap)
  static const consoleBg = Color(0xFF131315);
  static const consoleText = Color(0xFFD7D9DD);

  // Mod terahang
  static const lightBg = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF2F3F5);
  static const lightSurfaceHigh = Color(0xFFE3E5E8);
  static const lightOutline = Color(0xFFD8DBE0);
  static const lightTextPrimary = Color(0xFF060607);
  static const lightTextSecondary = Color(0xFF4E5058);
}

/// Skala ruang 4/8/12/16/24/32 — tiada nilai rawak dibenarkan.
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Radius sudut yang konsisten.
class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 100;
}

/// Tempoh & keluk animasi (150-300ms, easing lembut).
class AppMotion {
  AppMotion._();
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve ease = Curves.easeOutCubic;
}

/// Titik pecah layout adaptif.
class AppBreakpoints {
  AppBreakpoints._();
  static const double compact = 600;
  static const double maxContentWidth = 560;
}

/// Tema aplikasi (mod gelap ialah lalai).
class AppTheme {
  AppTheme._();

  static const fontFamily = 'Inter';

  static ThemeData dark() => _build(const _DarkPalette());
  static ThemeData light() => _build(const _LightPalette());

  static ThemeData _build(_Palette p) {
    final baseText = GoogleFonts.interTextTheme(
      p.isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
    );
    final textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: baseText.headlineSmall?.copyWith(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: baseText.titleLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      titleMedium: baseText.titleMedium?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      titleSmall: baseText.titleSmall?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
      bodyLarge: baseText.bodyLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w400, height: 1.45),
      bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.4),
      bodySmall: baseText.bodySmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, height: 1.35),
      labelLarge: baseText.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: baseText.labelMedium?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      labelSmall: baseText.labelSmall?.copyWith(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
    );

    final colorScheme = ColorScheme(
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      primary: AppColors.blurple,
      onPrimary: AppColors.onBlurple,
      primaryContainer: p.isDark ? AppColors.blurpleDark : const Color(0xFFDDE1FC),
      onPrimaryContainer: p.isDark ? const Color(0xFFE0E2FF) : AppColors.blurpleDark,
      secondary: p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark,
      onSecondary: Colors.white,
      secondaryContainer: p.isDark ? const Color(0x2E5865F2) : const Color(0xFFE4E7FD),
      onSecondaryContainer: p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.surfaceHigh,
      onSurfaceVariant: p.textSecondary,
      outline: p.outline,
      outlineVariant: p.outline,
      error: AppColors.danger,
      onError: Colors.white,
      errorContainer: const Color(0x2EF23F43),
      onErrorContainer: AppColors.danger,
      inverseSurface: p.isDark ? const Color(0xFFF2F3F5) : const Color(0xFF2B2D31),
      onInverseSurface: p.isDark ? const Color(0xFF1E1F22) : const Color(0xFFF2F3F5),
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.bg,
      fontFamily: fontFamily,
      textTheme: textTheme,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        systemOverlayStyle: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: p.outline.withValues(alpha: 0.55), width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.outline.withValues(alpha: 0.5), thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surfaceHigh,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textFaint),
        labelStyle: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
        helperStyle: textTheme.bodySmall?.copyWith(color: AppColors.textFaint),
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: p.outline.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.blurple, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blurple,
          foregroundColor: AppColors.onBlurple,
          disabledBackgroundColor: p.isDark ? const Color(0xFF3A3C46) : const Color(0xFFCCCDD6),
          disabledForegroundColor: p.isDark ? AppColors.textFaint : Colors.white70,
          minimumSize: const Size(48, 50),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 12),
          side: BorderSide(color: p.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: p.textSecondary,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected) ? const Color(0x2E5865F2) : Colors.transparent),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? (p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark)
                  : p.textSecondary),
          side: WidgetStatePropertyAll(BorderSide(color: p.outline)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.bg,
        indicatorColor: const Color(0x2E5865F2),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 23,
              color: states.contains(WidgetState.selected)
                  ? (p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark)
                  : AppColors.textFaint,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.bg,
        indicatorColor: const Color(0x2E5865F2),
        selectedIconTheme: IconThemeData(
            size: 23, color: p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark),
        unselectedIconTheme: const IconThemeData(size: 23, color: AppColors.textFaint),
        selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
            color: p.isDark ? AppColors.blurpleBright : AppColors.blurpleDark),
        unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(color: AppColors.textFaint),
        groupAlignment: -0.9,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.isDark ? p.surfaceHigh : const Color(0xFF2B2D31),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        elevation: 3,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: p.textSecondary),
        barrierColor: Colors.black54,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black54,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceHigh,
        side: BorderSide(color: p.outline.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        labelStyle: textTheme.labelMedium?.copyWith(color: p.textSecondary),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textFaint),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.blurple : p.outline),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.blurple : Colors.transparent),
        side: BorderSide(color: p.outline, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blurple,
        linearTrackColor: AppColors.outline,
        circularTrackColor: AppColors.outline,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: p.surface,
        collapsedBackgroundColor: p.surface,
        iconColor: p.textSecondary,
        collapsedIconColor: p.textSecondary,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.surfaceHigh, borderRadius: BorderRadius.circular(AppRadius.sm)),
        textStyle: textTheme.bodySmall?.copyWith(color: p.textPrimary),
      ),
    );
  }
}

abstract class _Palette {
  bool get isDark;
  Color get bg;
  Color get surface;
  Color get surfaceHigh;
  Color get outline;
  Color get textPrimary;
  Color get textSecondary;
}

class _DarkPalette implements _Palette {
  const _DarkPalette();
  @override bool get isDark => true;
  @override Color get bg => AppColors.bg;
  @override Color get surface => AppColors.surface;
  @override Color get surfaceHigh => AppColors.surfaceHigh;
  @override Color get outline => AppColors.outline;
  @override Color get textPrimary => AppColors.textPrimary;
  @override Color get textSecondary => AppColors.textSecondary;
}

class _LightPalette implements _Palette {
  const _LightPalette();
  @override bool get isDark => false;
  @override Color get bg => AppColors.lightBg;
  @override Color get surface => AppColors.lightSurface;
  @override Color get surfaceHigh => AppColors.lightSurfaceHigh;
  @override Color get outline => AppColors.lightOutline;
  @override Color get textPrimary => AppColors.lightTextPrimary;
  @override Color get textSecondary => AppColors.lightTextSecondary;
}
