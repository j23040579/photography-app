import 'package:flutter/material.dart';

abstract final class Palette {
  static const wine = Color(0xFF6D0808);
  static const ink = Color(0xFF2D0000);
  static const sage = Color(0xFF757D6F);
  static const cream = Color(0xFFEEEAD7);
  static const paper = Color(0xFFFAF8EF);
  static const line = Color(0xFFDEDAC8);
}

ThemeData photographTheme() => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: Palette.wine,
    primary: Palette.wine,
    secondary: Palette.sage,
    surface: Palette.paper,
    onSurface: Palette.ink,
  ),
  scaffoldBackgroundColor: Palette.cream,
  appBarTheme: const AppBarTheme(
    backgroundColor: Palette.cream,
    foregroundColor: Palette.ink,
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontFamily: 'Georgia',
      fontSize: 64,
      height: 1.05,
      fontWeight: FontWeight.w500,
      color: Palette.ink,
    ),
    displayMedium: TextStyle(
      fontFamily: 'Georgia',
      fontSize: 46,
      height: 1.1,
      color: Palette.ink,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Georgia',
      fontSize: 36,
      height: 1.12,
      color: Palette.ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Georgia',
      fontSize: 28,
      height: 1.2,
      color: Palette.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w600,
      color: Palette.ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: Palette.ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: Palette.ink),
    labelSmall: TextStyle(
      fontSize: 11,
      letterSpacing: 1.6,
      fontWeight: FontWeight.w600,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Palette.paper,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Palette.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Palette.line),
    ),
    contentPadding: const EdgeInsets.all(18),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  dividerColor: Palette.line,
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);

IconData categoryIcon(String category) => switch (category) {
  'restaurant' => Icons.restaurant_rounded,
  'party' => Icons.celebration_rounded,
  'travel' => Icons.explore_rounded,
  'outdoors' => Icons.landscape_rounded,
  'celebration' => Icons.cake_rounded,
  _ => Icons.wb_sunny_rounded,
};

String shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = Palette.sage});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
  );
}

class PaperCard extends StatelessWidget {
  const PaperCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Palette.paper,
      border: Border.all(color: Palette.line),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}
