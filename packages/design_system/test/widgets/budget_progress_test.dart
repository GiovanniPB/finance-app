import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  BudgetProgress budget(int spentMinor, int limitMinor) => BudgetProgress(
    category: 'Alimentação',
    spent: Money.fromMinor(spentMinor),
    limit: Money.fromMinor(limitMinor),
  );

  Color barColor(WidgetTester tester) {
    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    return indicator.valueColor!.value!;
  }

  group('BudgetProgress — limiares (RN-1.3)', () {
    test('abaixo de 80% é neutro', () {
      expect(budget(70000, 120000).tone, MoneyTone.neutral);
      expect(budget(0, 120000).tone, MoneyTone.neutral);
    });

    test('a partir de 80% é atenção', () {
      expect(budget(96000, 120000).tone, MoneyTone.warning);
      expect(budget(43200, 50000).tone, MoneyTone.warning);
    });

    test('exatamente 80% já é atenção', () {
      expect(budget(80, 100).tone, MoneyTone.warning);
    });

    test('acima de 100% é estourado', () {
      expect(budget(31840, 30000).tone, MoneyTone.over);
    });

    test('exatamente 100% ainda é atenção, não estourado', () {
      expect(budget(100, 100).tone, MoneyTone.warning);
    });
  });

  group('BudgetProgress — percentual', () {
    test('arredonda para inteiro', () {
      expect(budget(84210, 120000).percent, 70);
      expect(budget(43200, 50000).percent, 86);
      expect(budget(31840, 30000).percent, 106);
    });

    test('limite zero não divide por zero', () {
      final zero = budget(1000, 0);
      expect(zero.ratio, 0);
      expect(zero.percent, 0);
      expect(zero.tone, MoneyTone.neutral);
    });

    test('limite negativo é tratado como ausente', () {
      expect(budget(1000, -500).ratio, 0);
    });
  });

  group('BudgetProgress — renderização', () {
    testWidgets('mostra categoria, percentual e os dois valores', (
      tester,
    ) async {
      await pumpThemed(tester, budget(84210, 120000));

      expect(find.text('Alimentação'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('842,10'), findsOneWidget);
      expect(find.text('1.200,00'), findsOneWidget);
    });

    testWidgets('a barra usa a marca quando dentro do limite', (tester) async {
      await pumpThemed(tester, budget(70000, 120000));

      expect(barColor(tester), AppPalette.teal600);
    });

    testWidgets('a barra vira âmbar em atenção', (tester) async {
      await pumpThemed(tester, budget(43200, 50000));

      expect(barColor(tester), AppTokens.light().attention);
    });

    testWidgets('a barra vira vermelha quando estoura', (tester) async {
      await pumpThemed(tester, budget(31840, 30000));

      expect(barColor(tester), AppTokens.light().moneyOver);
    });

    testWidgets('a barra nunca passa de 100% preenchida', (tester) async {
      await pumpThemed(tester, budget(60000, 30000));

      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 1.0);
    });

    testWidgets('o percentual é colorido junto com a barra', (tester) async {
      await pumpThemed(tester, budget(31840, 30000));

      // Cor nunca sozinha: existe o rótulo "106%" ao lado da barra colorida.
      expect(textColor(tester, '106%'), AppTokens.light().moneyOver);
    });

    testWidgets('funciona no tema escuro', (tester) async {
      await pumpThemed(tester, budget(43200, 50000), dark: true);

      expect(barColor(tester), AppTokens.dark().attention);
    });
  });
}
