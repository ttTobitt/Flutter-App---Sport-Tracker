import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Zentrale Farb- und Style-Definitionen (Design A „Sportplatz“)
/// Hier änderst du das Aussehen der ganzen App an einer Stelle
class AppColors {
  static const background = Color(0xFFF4F1E8); // Kreide/Papier
  static const surface = Color(0xFFFFFFFF); // Karten
  static const surfaceBorder = Color(0xFFDDD7C6);
  static const track = Color(0xFFE6E0CF); // Hintergrund von Balken, Gitterlinien
  static const ink = Color(0xFF14251A); // Haupttext
  static const textMuted = Color(0xFF55604F);
  static const pitch = Color(0xFF2E6B45); // Rasengrün
  static const sprint = Color(0xFFC2410C); // Akzent: alles, was mit Sprints zu tun hat
  static const heat = Color(0xFFFFC400); // Heatmap auf dem Rasen
  static const success = Color(0xFF2E6B45);
  static const danger = Color(0xFFB42318);

  /// Farben der Geschwindigkeitszonen, von langsam (hell) bis Sprint
  static const zones = [
    Color(0xFFB9C9B6),
    Color(0xFF7FA487),
    Color(0xFF2E6B45),
    sprint,
  ];
}

/// Schmale, fette Schrift für Überschriften und große Zahlen
TextStyle displayStyle({double size = 34, Color color = AppColors.ink}) {
  return GoogleFonts.barlowCondensed(
    fontSize: size,
    fontWeight: FontWeight.w700,
    height: 1.0,
    color: color,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.pitch,
      primary: AppColors.pitch,
      secondary: AppColors.sprint,
      surface: AppColors.surface,
      error: AppColors.danger,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.barlowTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.barlow(
        color: AppColors.textMuted,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.pitch.withValues(alpha: 0.12),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.barlow(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.pitch,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.barlow(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppColors.surfaceBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: GoogleFonts.barlow(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.track,
        selectedBackgroundColor: AppColors.surface,
        foregroundColor: AppColors.textMuted,
        selectedForegroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.track),
        textStyle: GoogleFonts.barlow(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
  );
}
