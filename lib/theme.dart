import 'package:flutter/material.dart';

const ink = Color(0xFF1B1D1F);
const ground = Color(0xFFF4F2EE);
const line = Color(0xFFD6D2CA);
const muted = Color(0xFF5E5A53);
const cheap = Color(0xFF1E7A4C);
const amber = Color(0xFFE8A33D);
const warnBg = Color(0xFFFCEFD8);
const warnInk = Color(0xFF5A3E0E);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ink, surface: ground, primary: ink),
    scaffoldBackgroundColor: ground,
  );
  return base.copyWith(
    appBarTheme: const AppBarTheme(backgroundColor: ground, foregroundColor: ink, elevation: 0, centerTitle: false),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ground,
      indicatorColor: const Color(0xFFE6E2DA),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: line)),
    ),
  );
}

const titleStyle = TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.5);
const capsStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: muted);

class Card2 extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Card2({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: child,
      );
}

class FuelChips extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const FuelChips({super.key, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    Widget chip(String key, String label) {
      final on = value == key;
      return ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => onChanged(key),
        selectedColor: ink,
        backgroundColor: Colors.white,
        side: BorderSide(color: on ? ink : line),
        labelStyle: TextStyle(color: on ? Colors.white : ink, fontWeight: FontWeight.w600),
        shape: const StadiumBorder(),
      );
    }

    return Wrap(spacing: 8, children: [chip('petrol', 'Petrol'), chip('diesel', 'Diesel')]);
  }
}
