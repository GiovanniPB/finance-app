import 'package:flutter/material.dart';

/// Tema compartilhado do app. Ponto único de verdade para cores/tipografia.
/// Nesta fase é um scaffold enxuto (Material 3 + seed color); tokens e
/// componentes evoluem junto com a UI.
abstract final class AppTheme {
  /// Cor-semente da identidade visual.
  static const seedColor = Color(0xFF1E6F5C);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }
}
