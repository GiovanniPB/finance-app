import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  /// Cor de preenchimento efetiva do único swatch na árvore.
  Color fillOf(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(CategorySwatch),
        matching: find.byType(Container),
      ),
    );
    return (box.decoration! as BoxDecoration).color!;
  }

  group('AppTokens.colorsAt', () {
    testWidgets('índice fora da faixa dá a volta na paleta', (tester) async {
      await pumpThemed(tester, const SizedBox());
      final tokens = AppTheme.light().extension<AppTokens>()!;

      expect(tokens.colorsAt(tokens.categoryHues), tokens.colorsAt(0));
      expect(tokens.colorsAt(-1), tokens.colorsAt(1));
    });

    testWidgets('a paleta oferece seis matizes nos dois temas', (tester) async {
      await pumpThemed(tester, const SizedBox());

      expect(AppTheme.light().extension<AppTokens>()!.categoryHues, 6);
      expect(AppTheme.dark().extension<AppTokens>()!.categoryHues, 6);
    });
  });

  group('CategorySwatch', () {
    testWidgets('sem escolha, a cor sai do hash do id', (tester) async {
      await pumpThemed(
        tester,
        const CategorySwatch(categoryId: 'cat-1', icon: Icons.restaurant),
      );
      final tokens = AppTheme.light().extension<AppTokens>()!;

      expect(fillOf(tester), tokens.colorsForCategory('cat-1').fill);
    });

    testWidgets('a matiz escolhida vence o hash do id', (tester) async {
      await pumpThemed(
        tester,
        const CategorySwatch(
          categoryId: 'cat-1',
          icon: Icons.restaurant,
          colorIndex: 4,
        ),
      );
      final tokens = AppTheme.light().extension<AppTokens>()!;

      expect(fillOf(tester), tokens.colorsAt(4).fill);
      expect(fillOf(tester), isNot(tokens.colorsForCategory('cat-1').fill));
    });

    testWidgets('o construtor de marca ignora paleta de categoria', (
      tester,
    ) async {
      await pumpThemed(
        tester,
        const CategorySwatch.brand(icon: Icons.arrow_downward),
      );
      final tokens = AppTheme.light().extension<AppTokens>()!;

      expect(fillOf(tester), tokens.brandSubtle);
    });

    testWidgets('a escolha também vale no tema escuro', (tester) async {
      await pumpThemed(
        tester,
        const CategorySwatch(
          categoryId: 'cat-1',
          icon: Icons.restaurant,
          colorIndex: 2,
        ),
        dark: true,
      );
      final tokens = AppTheme.dark().extension<AppTokens>()!;

      expect(fillOf(tester), tokens.colorsAt(2).fill);
    });
  });
}
