import 'package:flutter/material.dart';

const Color upColor = Color(0xFF16C784);
const Color downColor = Color(0xFFEA3943);
const Color seed = Color(0xFF2962FF);

Color changeColor(double change, BuildContext context) =>
    change > 0 ? upColor : (change < 0 ? downColor : Theme.of(context).colorScheme.onSurfaceVariant);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
    surface: brightness == Brightness.dark ? const Color(0xFF0E1117) : const Color(0xFFF7F8FA),
    surfaceContainerLowest: brightness == Brightness.dark ? const Color(0xFF0B0D12) : Colors.white,
    surfaceContainerLow: brightness == Brightness.dark ? const Color(0xFF151922) : Colors.white,
    surfaceContainer: brightness == Brightness.dark ? const Color(0xFF1A1F2A) : const Color(0xFFF0F2F5),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.35), space: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      height: 68,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
  );
}
