import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppTheme', () {
    test('light usa Material 3 e brilho claro', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('dark usa Material 3 e brilho escuro', () {
      final theme = AppTheme.dark();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.brightness, Brightness.dark);
    });

    test('deriva o color scheme da cor-semente', () {
      expect(AppTheme.light().colorScheme, isNotNull);
      expect(AppTheme.seedColor, const Color(0xFF1E6F5C));
    });
  });
}
