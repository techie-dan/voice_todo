import 'package:flutter/material.dart';

/// The single seed colour; Material 3 derives the rest of the palette from it.
const Color _seed = Color(0xFF3D5AFE);

/// Corner radius shared by cards, sheets and tiles.
const double kCardRadius = 16;

/// Builds the app theme for [brightness].
///
/// Deliberately thin: the palette comes from [ColorScheme.fromSeed] and
/// individual widgets read their colours from `Theme.of(context).colorScheme`.
/// Keeping component-level styling at the call site avoids pinning this file
/// to theme-class signatures that shift between Flutter releases.
ThemeData buildTheme(Brightness brightness) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
}
