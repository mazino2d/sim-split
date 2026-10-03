import 'package:flutter/material.dart';

/// SimSplit design tokens: a minimal monochrome system with Be Vietnam Pro,
/// one positive accent for money owed to you and one muted warning tone for
/// money you owe. Everything else is black, white and greys.
abstract final class AppTheme {
  static const fontFamily = 'BeVietnamPro';

  /// Corner radii, from small controls to sheets.
  static const radiusS = 12.0;
  static const radiusM = 16.0;
  static const radiusL = 24.0;

  /// Horizontal page gutter used by every screen.
  static const gutter = 20.0;

  static ThemeData light() => _build(_lightScheme, MoneyColors.light);
  static ThemeData dark() => _build(_darkScheme, MoneyColors.dark);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF0A0A0A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEDEDED),
    onPrimaryContainer: Color(0xFF0A0A0A),
    secondary: Color(0xFF404040),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFF0F0F0),
    onSecondaryContainer: Color(0xFF0A0A0A),
    tertiary: Color(0xFF067647),
    onTertiary: Color(0xFFFFFFFF),
    error: Color(0xFFC4320A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEF3F2),
    onErrorContainer: Color(0xFF7A1A0A),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF0A0A0A),
    onSurfaceVariant: Color(0xFF6B6B6B),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F7F7),
    surfaceContainer: Color(0xFFF2F2F2),
    surfaceContainerHigh: Color(0xFFEDEDED),
    surfaceContainerHighest: Color(0xFFE6E6E6),
    outline: Color(0xFFCFCFCF),
    outlineVariant: Color(0xFFEBEBEB),
    inverseSurface: Color(0xFF0A0A0A),
    onInverseSurface: Color(0xFFF5F5F5),
    inversePrimary: Color(0xFFF5F5F5),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFF5F5F5),
    onPrimary: Color(0xFF0B0B0B),
    primaryContainer: Color(0xFF262626),
    onPrimaryContainer: Color(0xFFF5F5F5),
    secondary: Color(0xFFC7C7C7),
    onSecondary: Color(0xFF0B0B0B),
    secondaryContainer: Color(0xFF1F1F1F),
    onSecondaryContainer: Color(0xFFF5F5F5),
    tertiary: Color(0xFF47CD89),
    onTertiary: Color(0xFF0B0B0B),
    error: Color(0xFFF97066),
    onError: Color(0xFF0B0B0B),
    errorContainer: Color(0xFF3A1410),
    onErrorContainer: Color(0xFFFECDCA),
    surface: Color(0xFF0B0B0B),
    onSurface: Color(0xFFF5F5F5),
    onSurfaceVariant: Color(0xFFA3A3A3),
    surfaceContainerLowest: Color(0xFF000000),
    surfaceContainerLow: Color(0xFF141414),
    surfaceContainer: Color(0xFF1A1A1A),
    surfaceContainerHigh: Color(0xFF222222),
    surfaceContainerHighest: Color(0xFF2A2A2A),
    outline: Color(0xFF3D3D3D),
    outlineVariant: Color(0xFF242424),
    inverseSurface: Color(0xFFF5F5F5),
    onInverseSurface: Color(0xFF0B0B0B),
    inversePrimary: Color(0xFF0B0B0B),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    surfaceTint: Colors.transparent,
  );

  static ThemeData _build(ColorScheme cs, MoneyColors money) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      fontFamily: fontFamily,
    );
    final text = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
      headlineMedium: base.textTheme.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: base.textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium:
          base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall:
          base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge:
          base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );

    final stadium = WidgetStatePropertyAll<OutlinedBorder>(
      const StadiumBorder(),
    );
    const buttonPadding = WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 24),
    );
    final buttonText = WidgetStatePropertyAll<TextStyle?>(
      text.labelLarge?.copyWith(fontSize: 15),
    );
    OutlineInputBorder inputBorder([Color? color]) => OutlineInputBorder(
          borderSide: color == null
              ? BorderSide.none
              : BorderSide(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(radiusS),
        );

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: cs.surface,
      extensions: [money],
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cs.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusM),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: gutter),
        iconColor: cs.onSurfaceVariant,
        subtitleTextStyle:
            text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: stadium,
          padding: buttonPadding,
          textStyle: buttonText,
          minimumSize: const WidgetStatePropertyAll(Size(64, 52)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: stadium,
          padding: buttonPadding,
          textStyle: buttonText,
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          foregroundColor: WidgetStatePropertyAll(cs.onSurface),
          side: WidgetStatePropertyAll(BorderSide(color: cs.outline)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: stadium,
          textStyle: buttonText,
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? cs.onSurface.withValues(alpha: 0.38)
                : cs.onSurface,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: const StadiumBorder(),
        extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainer,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder(),
        enabledBorder: inputBorder(),
        disabledBorder: inputBorder(),
        focusedBorder: inputBorder(cs.onSurface),
        errorBorder: inputBorder(cs.error),
        focusedErrorBorder: inputBorder(cs.error),
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: cs.onSurface),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: cs.surfaceContainer,
        selectedColor: cs.primary,
        showCheckmark: false,
        labelStyle: text.labelLarge?.copyWith(color: cs.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(color: cs.onPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: buttonText,
          side: WidgetStatePropertyAll(BorderSide(color: cs.outline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? cs.primary : null,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? cs.onPrimary
                : cs.onSurface,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cs.onSurface,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
        indicatorColor: cs.onSurface,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: cs.outlineVariant,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: cs.onInverseSurface),
        actionTextColor: cs.onInverseSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusS),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusL)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.onSurface),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusL),
        ),
      ),
    );
  }
}

/// Semantic colours for money. Positive = others owe you; negative = you owe.
@immutable
class MoneyColors extends ThemeExtension<MoneyColors> {
  const MoneyColors({required this.positive, required this.negative});

  final Color positive;
  final Color negative;

  static const light = MoneyColors(
    positive: Color(0xFF067647),
    negative: Color(0xFFC4320A),
  );
  static const dark = MoneyColors(
    positive: Color(0xFF47CD89),
    negative: Color(0xFFF97066),
  );

  /// Colour for a signed amount; zero uses the muted text colour.
  Color forSign(int cents, ColorScheme cs) => cents > 0
      ? positive
      : cents < 0
          ? negative
          : cs.onSurfaceVariant;

  @override
  MoneyColors copyWith({Color? positive, Color? negative}) => MoneyColors(
        positive: positive ?? this.positive,
        negative: negative ?? this.negative,
      );

  @override
  MoneyColors lerp(MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  MoneyColors get money =>
      Theme.of(this).extension<MoneyColors>() ?? MoneyColors.light;
}

/// Tabular figures keep amounts aligned and stop digits jittering as they
/// change.
const tabularFigures = [FontFeature.tabularFigures()];
