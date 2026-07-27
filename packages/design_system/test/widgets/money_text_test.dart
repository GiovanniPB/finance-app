import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  const expense = Money.fromMinor(-14280);
  const income = Money.fromMinor(540000);

  group('MoneyText — a regra central do sistema', () {
    testWidgets('despesa não recebe cor semântica', (tester) async {
      await pumpThemed(tester, const MoneyText.expense(expense));

      final tokens = AppTokens.light();
      expect(textColor(tester, '-142,80'), tokens.moneyNeutral);
    });

    testWidgets('receita recebe a cor da marca e o sinal +', (tester) async {
      await pumpThemed(tester, const MoneyText.income(income));

      expect(find.text('+5.400,00'), findsOneWidget);
      expect(textColor(tester, '+5.400,00'), AppTokens.light().moneyPositive);
    });

    testWidgets('tom não-neutro também engrossa o peso', (tester) async {
      await pumpThemed(tester, const MoneyText.income(income));

      // Cor nunca é o único sinal: peso e prefixo carregam junto.
      expect(textStyleOf(tester, '+5.400,00').fontWeight, FontWeight.w600);
    });

    testWidgets('despesa mantém o peso base', (tester) async {
      await pumpThemed(tester, const MoneyText.expense(expense));

      expect(textStyleOf(tester, '-142,80').fontWeight, FontWeight.w500);
    });

    testWidgets('não adiciona + a um valor negativo', (tester) async {
      await pumpThemed(tester, const MoneyText.income(expense));

      expect(find.text('-142,80'), findsOneWidget);
      expect(find.text('+-142,80'), findsNothing);
    });

    testWidgets('sempre aplica figuras tabulares', (tester) async {
      await pumpThemed(tester, const MoneyText.expense(expense));

      final features = textStyleOf(tester, '-142,80').fontFeatures;
      expect(features, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('omite o símbolo por padrão e inclui quando pedido', (
      tester,
    ) async {
      await pumpThemed(tester, const MoneyText.expense(expense));
      expect(find.text('-142,80'), findsOneWidget);

      await pumpThemed(
        tester,
        const MoneyText.expense(expense, withSymbol: true),
      );
      expect(find.text(r'-R$ 142,80'), findsOneWidget);
    });

    testWidgets('expõe o valor com símbolo para leitores de tela', (
      tester,
    ) async {
      await pumpThemed(tester, const MoneyText.expense(expense));

      final text = tester.widget<Text>(find.text('-142,80'));
      expect(text.semanticsLabel, r'-R$ 142,80');
    });
  });

  group('MoneyText — tons de orçamento', () {
    testWidgets('warning usa a cor de atenção', (tester) async {
      await pumpThemed(
        tester,
        const MoneyText(income, tone: MoneyTone.warning),
      );

      expect(textColor(tester, '5.400,00'), AppTokens.light().moneyWarning);
    });

    testWidgets('over usa a cor de estourado', (tester) async {
      await pumpThemed(tester, const MoneyText(income, tone: MoneyTone.over));

      expect(textColor(tester, '5.400,00'), AppTokens.light().moneyOver);
    });

    testWidgets('warning e over não recebem prefixo +', (tester) async {
      await pumpThemed(
        tester,
        const MoneyText(income, tone: MoneyTone.warning),
      );

      expect(find.text('5.400,00'), findsOneWidget);
    });
  });

  group('MoneyText — tamanhos', () {
    testWidgets('balance usa 40px, o momento alto', (tester) async {
      await pumpThemed(
        tester,
        const MoneyText(income, size: MoneySize.balance),
      );

      expect(textStyleOf(tester, '5.400,00').fontSize, 40);
    });

    testWidgets('large, normal e small têm tamanhos distintos', (tester) async {
      await pumpThemed(tester, const MoneyText(income, size: MoneySize.large));
      final large = textStyleOf(tester, '5.400,00').fontSize;

      await pumpThemed(tester, const MoneyText(income));
      final normal = textStyleOf(tester, '5.400,00').fontSize;

      await pumpThemed(tester, const MoneyText(income, size: MoneySize.small));
      final small = textStyleOf(tester, '5.400,00').fontSize;

      expect(large, greaterThan(normal!));
      expect(normal, greaterThan(small!));
    });
  });

  group('MoneyText — tema escuro', () {
    testWidgets('resolve as cores do tema escuro', (tester) async {
      await pumpThemed(tester, const MoneyText.income(income), dark: true);

      expect(textColor(tester, '+5.400,00'), AppTokens.dark().moneyPositive);
    });

    testWidgets('a receita muda de cor entre os temas', (tester) async {
      expect(
        AppTokens.dark().moneyPositive,
        isNot(AppTokens.light().moneyPositive),
      );
    });
  });
}
