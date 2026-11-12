import 'package:flutter/material.dart';

/// Design tokens from design/DESIGN.md (the `--cb-*` variables).
@immutable
class CbColors extends ThemeExtension<CbColors> {
  const CbColors({
    required this.ink,
    required this.muted,
    required this.line,
    required this.soft,
    required this.card,
    required this.page,
    required this.green,
    required this.greenText,
    required this.greenSoft,
    required this.dark,
    required this.amber,
    required this.amberSoft,
    required this.red,
    required this.redSoft,
    required this.poolCard,
    required this.tray,
  });

  final Color ink;
  final Color muted;
  final Color line;
  final Color soft;
  final Color card;
  final Color page;
  final Color green;

  /// Green used for text ("good" values, links): lighter in dark mode for contrast.
  final Color greenText;
  final Color greenSoft;
  final Color dark;
  final Color amber;
  final Color amberSoft;
  final Color red;
  final Color redSoft;
  final Color poolCard;

  /// Grey tray behind receipt paper.
  final Color tray;

  static const light = CbColors(
    ink: Color(0xFF16201B),
    muted: Color(0xFF56625B),
    line: Color(0xFFE1E5E0),
    soft: Color(0xFFF4F6F3),
    card: Color(0xFFFFFFFF),
    page: Color(0xFFF4F6F3),
    green: Color(0xFF0E6B4A),
    greenText: Color(0xFF0E6B4A),
    greenSoft: Color(0xFFE4F1EA),
    dark: Color(0xFF14201A),
    amber: Color(0xFF8A4B08),
    amberSoft: Color(0xFFFDF1DD),
    red: Color(0xFFB42318),
    redSoft: Color(0xFFFDECEA),
    poolCard: Color(0xFFF1F7F3),
    tray: Color(0xFFE4E9E4),
  );

  static const darkMode = CbColors(
    ink: Color(0xFFEEF2EF),
    muted: Color(0xFFA3B0A9),
    line: Color(0x1AFFFFFF),
    soft: Color(0x0AFFFFFF),
    card: Color(0xFF18181B),
    page: Color(0xFF0E0F10),
    green: Color(0xFF0E6B4A),
    greenText: Color(0xFF6FD3A5),
    greenSoft: Color(0x400E6B4A),
    dark: Color(0xFF14201A),
    amber: Color(0xFFF2B766),
    amberSoft: Color(0x29F2B766),
    red: Color(0xFFFF8A80),
    redSoft: Color(0x29FF8A80),
    poolCard: Color(0x1F0E6B4A),
    tray: Color(0xFF26272B),
  );

  @override
  CbColors copyWith() => this;

  @override
  CbColors lerp(ThemeExtension<CbColors>? other, double t) {
    if (other is! CbColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CbColors(
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      soft: l(soft, other.soft),
      card: l(card, other.card),
      page: l(page, other.page),
      green: l(green, other.green),
      greenText: l(greenText, other.greenText),
      greenSoft: l(greenSoft, other.greenSoft),
      dark: l(dark, other.dark),
      amber: l(amber, other.amber),
      amberSoft: l(amberSoft, other.amberSoft),
      red: l(red, other.red),
      redSoft: l(redSoft, other.redSoft),
      poolCard: l(poolCard, other.poolCard),
      tray: l(tray, other.tray),
    );
  }
}

/// Chart series, always in this order.
class SeriesColors {
  SeriesColors._();

  static const pool = Color(0xFF0E6B4A);
  static const food = Color(0xFFD08A2E);
  static const drinks = Color(0xFF9CC5B0);
  static const snacks = Color(0xFFE9C98F);

  static Color forKey(String key) => switch (key) {
    'pool' => pool,
    'food' => food,
    'drinks' => drinks,
    _ => snacks,
  };

  /// Busy-hours bars shade by occupancy.
  static Color occupancy(double pct) => pct >= 75
      ? const Color(0xFF0E6B4A)
      : pct >= 40
      ? const Color(0xFF5FA383)
      : const Color(0xFFC4DCCF);
}

extension CbContext on BuildContext {
  CbColors get cb => Theme.of(this).extension<CbColors>()!;
}

const tabular = [FontFeature.tabularFigures()];

/// Type scale.
class CbText {
  CbText._();

  static const heading = 'SpaceGrotesk';

  static TextStyle pageTitle(BuildContext c) =>
      TextStyle(fontFamily: heading, fontSize: 28, fontWeight: FontWeight.w700, color: c.cb.ink, height: 1.15);

  static TextStyle cardTitle(BuildContext c) => TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.cb.ink);

  static TextStyle label(BuildContext c) => TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.cb.muted);

  static TextStyle muted(BuildContext c, [double size = 13]) => TextStyle(fontSize: size, color: c.cb.muted);

  static TextStyle th(BuildContext c) =>
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: c.cb.muted);

  static TextStyle num(BuildContext c, {double size = 14, FontWeight weight = FontWeight.w400, Color? color}) =>
      TextStyle(fontSize: size, fontWeight: weight, color: color ?? c.cb.ink, fontFeatures: tabular);

  static TextStyle big(BuildContext c, {double size = 26, Color? color}) => TextStyle(
    fontFamily: heading,
    fontSize: size,
    fontWeight: FontWeight.w700,
    color: color ?? c.cb.ink,
    fontFeatures: tabular,
    height: 1.1,
  );
}

ThemeData buildTheme(Brightness brightness) {
  final cb = brightness == Brightness.light ? CbColors.light : CbColors.darkMode;
  final scheme = ColorScheme.fromSeed(
    seedColor: cb.green,
    brightness: brightness,
    primary: cb.green,
    onPrimary: Colors.white,
    surface: cb.card,
    onSurface: cb.ink,
    error: cb.red,
  );
  final radius10 = BorderRadius.circular(10);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: cb.page,
    extensions: [cb],
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: cb.ink, displayColor: cb.ink)
        .copyWith(
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14, color: cb.ink),
          // Text fields and dropdowns: 14.5 px, like the design inputs.
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 14.5, color: cb.ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w400, color: cb.ink),
        ),
    dividerTheme: DividerThemeData(color: cb.line, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: cb.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cb.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cb.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: cb.line,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cb.ink,
        backgroundColor: cb.card,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: BorderSide(color: cb.line),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
        shape: RoundedRectangleBorder(borderRadius: radius10),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cb.greenText,
        minimumSize: const Size(44, 40),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Inter'),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: cb.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      hintStyle: TextStyle(color: cb.muted, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: BorderSide(color: cb.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: BorderSide(color: cb.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: BorderSide(color: cb.green, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: BorderSide(color: cb.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius10,
        borderSide: BorderSide(color: cb.red, width: 2),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? cb.green : null),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? cb.green : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cb.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cb.dark,
      contentTextStyle: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
      shape: RoundedRectangleBorder(borderRadius: radius10),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: cb.greenText,
      unselectedLabelColor: cb.muted,
      indicatorColor: cb.green,
      dividerColor: cb.line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter'),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, fontFamily: 'Inter'),
    ),
    popupMenuTheme: PopupMenuThemeData(color: cb.card, surfaceTintColor: Colors.transparent),
    appBarTheme: AppBarTheme(
      backgroundColor: cb.dark,
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    datePickerTheme: DatePickerThemeData(backgroundColor: cb.card, surfaceTintColor: Colors.transparent),
    timePickerTheme: TimePickerThemeData(backgroundColor: cb.card),
  );
}
